// Skill Tree Loadouts: full skill-tree presets.
// A preset stores the whole tree (every bought skill and its level), the equipped skill
// slots, the skill mutagens and the Blood and Wine mutation. Loading one refunds every tree
// point (same as a Potion of Clearance, without using one) and buys the saved tree back with
// the player's own points, then re-equips slots, mutation and mutagens.

function StlPresetCount() : int
{
	return 5;
}

// extra hidden preset holding the build that was active before the last load (stl_undo)
function StlUndoIndex() : int
{
	return StlPresetCount();
}

class CStlPreset
{
	saved var used			: bool;
	saved var label			: string;
	saved var treeSkills	: array< ESkill >;
	saved var treeLevels	: array< int >;
	saved var slotIds		: array< int >;
	saved var slotSkills	: array< ESkill >;
	saved var mutagenSlots	: array< EEquipmentSlots >;
	saved var mutagenNames	: array< name >;
	saved var mutation		: EPlayerMutationType;
}

class CStlData
{
	saved var presets : array< CStlPreset >;

	// index 0..StlPresetCount()-1 = player presets, StlUndoIndex() = undo backup
	public function Get( idx : int ) : CStlPreset
	{
		while ( presets.Size() < StlPresetCount() + 1 )
		{
			presets.PushBack( new CStlPreset in this );
		}
		if ( idx < 0 || idx >= presets.Size() )
		{
			return NULL;
		}
		return presets[ idx ];
	}

	public function DisplayName( idx : int ) : string
	{
		var p : CStlPreset;

		p = Get( idx );
		if ( p && p.label != "" )
		{
			return p.label;
		}
		if ( idx == StlUndoIndex() )
		{
			return StlLoc( "stl_previous_build", "Previous build" );
		}
		return StlLocF( "stl_preset_name", "Preset $0$", IntToString( idx + 1 ) );
	}
}

// what could not be restored by a load
struct SStlLoadReport
{
	var missingLevels	: int;
	var failedSkills	: array< ESkill >;
	var missingSlots	: int;
	var savedSlots		: int;
	var missingMutagens	: int;
	var mutationFailed	: bool;
	var pointsLeft		: int;
}

@addField(W3PlayerWitcher)
saved var stlData : CStlData;

@addMethod(W3PlayerWitcher) function StlGetData() : CStlData
{
	if ( !stlData )
	{
		stlData = new CStlData in this;
	}
	return stlData;
}

// ---- save ----

@addMethod(W3PlayerWitcher) function StlSave( idx : int ) : bool
{
	var p : CStlPreset;
	var sk : SSkill;
	var slots : array< SSkillSlot >;
	var muts : array< SMutagenSlot >;
	var item : SItemUniqueId;
	var i, maxSkill : int;

	p = StlGetData().Get( idx );
	if ( !p )
	{
		return false;
	}

	p.treeSkills.Clear();
	p.treeLevels.Clear();
	p.slotIds.Clear();
	p.slotSkills.Clear();
	p.mutagenSlots.Clear();
	p.mutagenNames.Clear();

	// tree: every bought, non-core, non-temporary skill with its level
	maxSkill = EnumGetMax( 'ESkill' );
	for ( i = 0; i <= maxSkill; i += 1 )
	{
		sk = GetPlayerSkill( (ESkill)i );
		if ( sk.skillType == S_SUndefined || sk.isCoreSkill || sk.isTemporary || sk.level <= 0 )
		{
			continue;
		}
		p.treeSkills.PushBack( sk.skillType );
		p.treeLevels.PushBack( sk.level );
	}

	slots = GetSkillSlots();
	for ( i = 0; i < slots.Size(); i += 1 )
	{
		if ( slots[ i ].socketedSkill != S_SUndefined )
		{
			p.slotIds.PushBack( slots[ i ].id );
			p.slotSkills.PushBack( slots[ i ].socketedSkill );
		}
	}

	muts = GetPlayerSkillMutagens();
	for ( i = 0; i < muts.Size(); i += 1 )
	{
		if ( GetItemEquippedOnSlot( muts[ i ].equipmentSlot, item ) )
		{
			p.mutagenSlots.PushBack( muts[ i ].equipmentSlot );
			p.mutagenNames.PushBack( inv.GetItemName( item ) );
		}
	}

	p.mutation = GetEquippedMutationType();
	p.used = true;
	return true;
}

// ---- load ----

@addMethod(W3PlayerWitcher) function StlLoad( idx : int, out report : SStlLoadReport ) : bool
{
	var p : CStlPreset;
	var failed : array< ESkill >;

	p = StlGetData().Get( idx );
	if ( !p || !p.used || IsInCombat() )
	{
		return false;
	}

	// keep the current build so a bad load can be undone
	if ( idx != StlUndoIndex() )
	{
		StlSave( StlUndoIndex() );
	}

	// unequips skills + mutagens and refunds all tree points; mutation points are kept
	ResetCharacterDev();

	report.missingLevels = StlRebuyTree( p, failed );
	report.failedSkills = failed;

	// mutation before slots: it decides whether the 4 extra slots can be used
	if ( p.mutation != GetEquippedMutationType() )
	{
		report.mutationFailed = !SetEquippedMutation( p.mutation );
	}

	report.savedSlots = p.slotIds.Size();
	report.missingSlots = StlEquipSlots( p );
	report.missingMutagens = StlEquipMutagens( p );
	report.pointsLeft = levelManager.GetPointsFree( ESkillPoint );
	return true;
}

// Same purchase rule as the skills screen in use. CanLearnSkill checks dependencies (and the
// tier threshold for skills that are neither reworked nor unchanged-legacy) and free points.
// The Remastered screen ignores requiredPointsSpent for every skill (it sends
// 'hasRequiredPointsSpent' = true), but the legacy screen locks by it.
@addMethod(W3PlayerWitcher) function StlCanBuy( skill : ESkill, legacyTree : bool ) : bool
{
	if ( !CanLearnSkill( skill ) )
	{
		return false;
	}
	return !legacyTree || HasSpentEnoughPoints( skill );
}

function StlUsingLegacyTree() : bool
{
	return (bool)theGame.GetInGameConfigWrapper().GetVarValue( 'RemasterCombat', 'UseLegacySkillTree' );
}

// Buys the preset's tree back, one level at a time. Skills are tried in ascending order of
// the points their tier requires, and passes repeat until nothing more can be bought, so
// tier thresholds and skill dependencies (Remastered tree) are met in any order.
// Returns the number of levels that could not be bought; 'failed' lists those skills.
@addMethod(W3PlayerWitcher) function StlRebuyTree( p : CStlPreset, out failed : array< ESkill > ) : int
{
	var legacyTree : bool;
	var order : array< int >;
	var tiers : array< int >;
	var sk : SSkill;
	var skill : ESkill;
	var target, before, missing, i, j, tmp : int;
	var progress : bool;

	legacyTree = StlUsingLegacyTree();

	// sort preset entries by required points (insertion sort on indexes)
	for ( i = 0; i < p.treeSkills.Size(); i += 1 )
	{
		order.PushBack( i );
		sk = GetPlayerSkill( p.treeSkills[ i ] );
		tiers.PushBack( sk.requiredPointsSpent );
	}
	for ( i = 1; i < order.Size(); i += 1 )
	{
		j = i;
		while ( j > 0 && tiers[ order[ j - 1 ] ] > tiers[ order[ j ] ] )
		{
			tmp = order[ j - 1 ];
			order[ j - 1 ] = order[ j ];
			order[ j ] = tmp;
			j -= 1;
		}
	}

	progress = true;
	while ( progress )
	{
		progress = false;
		for ( i = 0; i < order.Size(); i += 1 )
		{
			skill = p.treeSkills[ order[ i ] ];
			target = Min( p.treeLevels[ order[ i ] ], GetSkillMaxLevel( skill ) );
			while ( StlBoughtLevel( skill ) < target && StlCanBuy( skill, legacyTree ) )
			{
				before = StlBoughtLevel( skill );
				AddSkill( skill );
				if ( StlBoughtLevel( skill ) <= before )
				{
					break;
				}
				progress = true;
			}
		}
	}

	for ( i = 0; i < p.treeSkills.Size(); i += 1 )
	{
		skill = p.treeSkills[ i ];
		target = Min( p.treeLevels[ i ], GetSkillMaxLevel( skill ) );
		if ( StlBoughtLevel( skill ) < target )
		{
			missing += target - StlBoughtLevel( skill );
			failed.PushBack( skill );
		}
	}
	return missing;
}

// level actually bought (W3PlayerWitcher.GetSkillLevel can include bonuses)
@addMethod(W3PlayerWitcher) function StlBoughtLevel( skill : ESkill ) : int
{
	return ( (W3PlayerAbilityManager)abilityManager ).GetBoughtSkillLevel( skill );
}

// returns the number of saved skills that could not be put back in their slot
@addMethod(W3PlayerWitcher) function StlEquipSlots( p : CStlPreset ) : int
{
	var slots : array< SSkillSlot >;
	var missing, i, j : int;
	var placed : bool;

	slots = GetSkillSlots();
	for ( i = 0; i < p.slotIds.Size(); i += 1 )
	{
		placed = false;
		if ( HasLearnedSkill( p.slotSkills[ i ] ) )
		{
			for ( j = 0; j < slots.Size(); j += 1 )
			{
				if ( slots[ j ].id == p.slotIds[ i ] && slots[ j ].unlocked )
				{
					placed = EquipSkill( p.slotSkills[ i ], p.slotIds[ i ] );
					break;
				}
			}
		}
		if ( !placed )
		{
			missing += 1;
		}
	}
	return missing;
}

// returns the number of saved mutagens that could not be equipped
@addMethod(W3PlayerWitcher) function StlEquipMutagens( p : CStlPreset ) : int
{
	var pam : W3PlayerAbilityManager;
	var item : SItemUniqueId;
	var missing, i : int;

	pam = (W3PlayerAbilityManager)abilityManager;
	for ( i = 0; i < p.mutagenSlots.Size(); i += 1 )
	{
		if ( pam.IsSkillMutagenSlotUnlocked( p.mutagenSlots[ i ] )
			&& StlFindFreeItem( p.mutagenNames[ i ], item )
			&& EquipItemInGivenSlot( item, p.mutagenSlots[ i ], false ) )
		{
			continue;
		}
		missing += 1;
	}
	return missing;
}

// an unequipped inventory item with this name
@addMethod(W3PlayerWitcher) function StlFindFreeItem( itemName : name, out item : SItemUniqueId ) : bool
{
	var ids : array< SItemUniqueId >;
	var i : int;

	if ( !IsNameValid( itemName ) )
	{
		return false;
	}
	ids = inv.GetItemsByName( itemName );
	for ( i = 0; i < ids.Size(); i += 1 )
	{
		if ( !IsItemEquipped( ids[ i ] ) )
		{
			item = ids[ i ];
			return true;
		}
	}
	return false;
}

// skill points a preset's tree costs
@addMethod(W3PlayerWitcher) function StlPresetCost( p : CStlPreset ) : int
{
	var sk : SSkill;
	var cost, i : int;

	for ( i = 0; i < p.treeSkills.Size(); i += 1 )
	{
		sk = GetPlayerSkill( p.treeSkills[ i ] );
		cost += sk.cost * p.treeLevels[ i ];
	}
	return cost;
}

// points the tree can use after a refund (mutation points stay spent)
@addMethod(W3PlayerWitcher) function StlTreePointsAvailable() : int
{
	return levelManager.GetPointsFree( ESkillPoint ) + levelManager.GetPointsUsed( ESkillPoint )
		- ( (W3PlayerAbilityManager)abilityManager ).GetMutationsUsedSkillPoints();
}

// refunds every tree point without a potion; the current build goes to the undo slot
@addMethod(W3PlayerWitcher) function StlResetTree() : bool
{
	if ( IsInCombat() )
	{
		return false;
	}
	StlSave( StlUndoIndex() );
	ResetCharacterDev();
	return true;
}

// ---- character menu refresh ----
// The skills screen caches what it shows; after a change made outside of it (console),
// redraw it the same way it redraws itself after buying or equipping a skill.

@addMethod(CR4CharacterDupeMenu) function StlRefresh()
{
	var slots : array< SSkillSlot >;
	var i : int;

	slots = thePlayer.GetSkillSlots();
	for ( i = 0; i < slots.Size(); i += 1 )
	{
		m_fxClearSkillSlot.InvokeSelfOneArg( FlashArgInt( slots[ i ].id ) );
	}
	UpdateData( true );
	UpdateMasterMutation();
}

@addMethod(CR4CharacterMenu) function StlRefresh()
{
	var slots : array< SSkillSlot >;
	var i : int;

	slots = thePlayer.GetSkillSlots();
	for ( i = 0; i < slots.Size(); i += 1 )
	{
		m_fxClearSkillSlot.InvokeSelfOneArg( FlashArgInt( slots[ i ].id ) );
	}
	UpdateData( true );
	UpdateMasterMutation();
}

// ---- skills screen UI (blob0.bundle, built from ui\scripts by tools\build-ui.ps1) ----

// sent by the modded panel_character_dupe when it opens; for now only proves the bundle loads
@addMethod(CR4CharacterDupeMenu) event OnStlUiReady()
{
	StlNotify( "Skill Tree Loadouts: UI loaded" );
}

// redraws the skills screen if it is the menu currently shown
function StlRefreshCharacterMenu()
{
	var root : CR4MenuBase;
	var last : CR4MenuBase;
	var dupe : CR4CharacterDupeMenu;
	var legacy : CR4CharacterMenu;

	root = (CR4MenuBase)theGame.GetGuiManager().GetRootMenu();
	if ( !root )
	{
		return;
	}
	last = root.GetLastChild();
	dupe = (CR4CharacterDupeMenu)last;
	if ( dupe )
	{
		dupe.StlRefresh();
		return;
	}
	legacy = (CR4CharacterMenu)last;
	if ( legacy )
	{
		legacy.StlRefresh();
	}
}

// ---- notifications ----

// Mod text from <lang>.w3strings (strings/*.csv); the English fallback is used when the game
// language has no translation for the mod.
function StlLoc( key : string, fallback : string ) : string
{
	var s : string;

	s = GetLocStringByKeyExt( key );
	if ( s == "" )
	{
		return fallback;
	}
	return s;
}

// StlLoc with $0$, $1$, $2$ replaced by the given values. Same "$X$" style as the game's own
// strings: with {0} markers the game dropped the spaces around them.
function StlLocF( key : string, fallback : string, optional a : string, optional b : string, optional c : string ) : string
{
	var s : string;

	s = StlLoc( key, fallback );
	s = StrReplaceAll( s, "$0$", a );
	s = StrReplaceAll( s, "$1$", b );
	s = StrReplaceAll( s, "$2$", c );
	return s;
}

function StlCombatDenied()
{
	StlNotify( GetLocStringByKeyExt( "menu_cannot_perform_action_combat" ) );
}

// localized skill name (game language), or its internal name if it has none
function StlSkillDisplayName( skill : ESkill ) : string
{
	var s : string;

	s = GetLocStringByKeyExt( thePlayer.GetSkillLocalisationKeyName( skill ) );
	if ( s == "" )
	{
		s = NameToString( SkillEnumToName( skill ) );
	}
	return s;
}

function StlNotify( msg : string )
{
	theGame.GetGuiManager().ShowNotification( msg, 6000 );
}

function StlReportText( report : SStlLoadReport ) : string
{
	var msg : string;
	var i : int;

	if ( report.missingLevels > 0 )
	{
		msg += "<br>" + StlLocF( "stl_levels_not_bought", "$0$ skill level(s) could not be bought:",
			IntToString( report.missingLevels ) );
		for ( i = 0; i < report.failedSkills.Size() && i < 6; i += 1 )
		{
			msg += "<br>- " + StlSkillDisplayName( report.failedSkills[ i ] );
		}
		if ( report.failedSkills.Size() > 6 )
		{
			msg += "<br>- ...";
		}
	}
	if ( report.mutationFailed )
	{
		msg += "<br>" + StlLoc( "stl_mutation_failed", "Mutation could not be equipped" );
	}
	msg += "<br>" + StlLocF( "stl_slots_restored", "Slotted skills: $0$ / $1$",
		IntToString( report.savedSlots - report.missingSlots ), IntToString( report.savedSlots ) );
	if ( report.missingMutagens > 0 )
	{
		msg += "<br>" + StlLocF( "stl_mutagens_missing", "$0$ mutagen(s) missing",
			IntToString( report.missingMutagens ) );
	}
	msg += "<br>" + StlLocF( "stl_free_points", "Free skill points: $0$", IntToString( report.pointsLeft ) );
	return msg;
}

// "Slotted skills: N" + "Mutagens: N" lines of a preset
function StlPresetSummary( p : CStlPreset ) : string
{
	return "<br>" + StlLocF( "stl_slots_count", "Slotted skills: $0$", IntToString( p.slotIds.Size() ) )
		+ "<br>" + StlLocF( "stl_mutagens_count", "Mutagens: $0$", IntToString( p.mutagenSlots.Size() ) );
}

function StlValidIndex( n : int ) : bool
{
	if ( n < 1 || n > StlPresetCount() )
	{
		StlNotify( StlLocF( "stl_bad_index", "Preset number must be 1..$0$", IntToString( StlPresetCount() ) ) );
		return false;
	}
	return true;
}

function StlLoadAndNotify( idx : int )
{
	var w : W3PlayerWitcher;
	var report : SStlLoadReport;

	w = GetWitcherPlayer();
	if ( w.IsInCombat() )
	{
		StlCombatDenied();
		return;
	}
	if ( !w.StlLoad( idx, report ) )
	{
		StlNotify( StlLocF( "stl_empty", "$0$ is empty", w.StlGetData().DisplayName( idx ) ) );
		return;
	}
	StlRefreshCharacterMenu();
	StlNotify( StlLocF( "stl_loaded", "$0$ loaded", w.StlGetData().DisplayName( idx ) ) + StlReportText( report ) );
}

// ---- debug console ----

exec function stl_save( n : int )
{
	var w : W3PlayerWitcher;
	var p : CStlPreset;

	w = GetWitcherPlayer();
	if ( !StlValidIndex( n ) )
	{
		return;
	}
	if ( w.IsInCombat() )
	{
		StlCombatDenied();
		return;
	}
	if ( w.StlSave( n - 1 ) )
	{
		p = w.StlGetData().Get( n - 1 );
		StlNotify( StlLocF( "stl_saved", "$0$ saved ($1$ skills, $2$ points)", w.StlGetData().DisplayName( n - 1 ),
			IntToString( p.treeSkills.Size() ), IntToString( w.StlPresetCost( p ) ) )
			+ StlPresetSummary( p ) );
	}
}

exec function stl_load( n : int )
{
	if ( StlValidIndex( n ) )
	{
		StlLoadAndNotify( n - 1 );
	}
}

// refunds all tree points (like a Potion of Clearance, none used); stl_undo restores
exec function stl_reset()
{
	var w : W3PlayerWitcher;

	w = GetWitcherPlayer();
	if ( !w.StlResetTree() )
	{
		StlCombatDenied();
		return;
	}
	StlRefreshCharacterMenu();
	StlNotify( StlLoc( "stl_reset_done", "Skill tree reset" ) + "<br>"
		+ StlLocF( "stl_free_points", "Free skill points: $0$", IntToString( w.levelManager.GetPointsFree( ESkillPoint ) ) ) );
}

// reloads the build that was active before the last stl_load / stl_reset
exec function stl_undo()
{
	StlLoadAndNotify( StlUndoIndex() );
}

exec function stl_name( n : int, newName : string )
{
	var w : W3PlayerWitcher;
	var p : CStlPreset;

	w = GetWitcherPlayer();
	if ( StlValidIndex( n ) )
	{
		p = w.StlGetData().Get( n - 1 );
		p.label = StrLeft( newName, 24 );
		StlNotify( w.StlGetData().DisplayName( n - 1 ) );
	}
}

exec function stl_info( n : int )
{
	var w : W3PlayerWitcher;
	var p : CStlPreset;
	var available : int;

	w = GetWitcherPlayer();
	if ( !StlValidIndex( n ) )
	{
		return;
	}
	p = w.StlGetData().Get( n - 1 );
	if ( !p.used )
	{
		StlNotify( StlLocF( "stl_empty", "$0$ is empty", w.StlGetData().DisplayName( n - 1 ) ) );
		return;
	}
	available = w.StlTreePointsAvailable();
	StlNotify( w.StlGetData().DisplayName( n - 1 )
		+ "<br>" + StlLocF( "stl_tree_skills", "Tree skills: $0$", IntToString( p.treeSkills.Size() ) )
		+ "<br>" + StlLocF( "stl_cost", "Cost: $0$ / $1$ points", IntToString( w.StlPresetCost( p ) ), IntToString( available ) )
		+ StlPresetSummary( p ) );
}
