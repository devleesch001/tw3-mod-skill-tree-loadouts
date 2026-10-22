// modTrueSkillPresets: full skill-tree presets.
// A preset stores the whole tree (every bought skill and its level), the equipped skill
// slots, the skill mutagens and the Blood and Wine mutation. Loading one refunds every tree
// point (same as a Potion of Clearance, without using one) and buys the saved tree back with
// the player's own points, then re-equips slots, mutation and mutagens.

function TspPresetCount() : int
{
	return 5;
}

// extra hidden preset holding the build that was active before the last load (tsp_undo)
function TspUndoIndex() : int
{
	return TspPresetCount();
}

class CTspPreset
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

class CTspData
{
	saved var presets : array< CTspPreset >;

	// index 0..TspPresetCount()-1 = player presets, TspUndoIndex() = undo backup
	public function Get( idx : int ) : CTspPreset
	{
		while ( presets.Size() < TspPresetCount() + 1 )
		{
			presets.PushBack( new CTspPreset in this );
		}
		if ( idx < 0 || idx >= presets.Size() )
		{
			return NULL;
		}
		return presets[ idx ];
	}

	public function DisplayName( idx : int ) : string
	{
		var p : CTspPreset;

		p = Get( idx );
		if ( p && p.label != "" )
		{
			return p.label;
		}
		if ( idx == TspUndoIndex() )
		{
			return "Previous build";
		}
		return "Preset " + IntToString( idx + 1 );
	}
}

// what could not be restored by a load
struct STspLoadReport
{
	var missingLevels	: int;
	var missingSlots	: int;
	var savedSlots		: int;
	var missingMutagens	: int;
	var mutationFailed	: bool;
	var pointsLeft		: int;
}

@addField(W3PlayerWitcher)
saved var tspData : CTspData;

@addMethod(W3PlayerWitcher) function TspGetData() : CTspData
{
	if ( !tspData )
	{
		tspData = new CTspData in this;
	}
	return tspData;
}

// ---- save ----

@addMethod(W3PlayerWitcher) function TspSave( idx : int ) : bool
{
	var p : CTspPreset;
	var sk : SSkill;
	var slots : array< SSkillSlot >;
	var muts : array< SMutagenSlot >;
	var item : SItemUniqueId;
	var i, maxSkill : int;

	p = TspGetData().Get( idx );
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

@addMethod(W3PlayerWitcher) function TspLoad( idx : int, out report : STspLoadReport ) : bool
{
	var p : CTspPreset;

	p = TspGetData().Get( idx );
	if ( !p || !p.used || IsInCombat() )
	{
		return false;
	}

	// keep the current build so a bad load can be undone
	if ( idx != TspUndoIndex() )
	{
		TspSave( TspUndoIndex() );
	}

	// unequips skills + mutagens and refunds all tree points; mutation points are kept
	ResetCharacterDev();

	report.missingLevels = TspRebuyTree( p );

	// mutation before slots: it decides whether the 4 extra slots can be used
	if ( p.mutation != GetEquippedMutationType() )
	{
		report.mutationFailed = !SetEquippedMutation( p.mutation );
	}

	report.savedSlots = p.slotIds.Size();
	report.missingSlots = TspEquipSlots( p );
	report.missingMutagens = TspEquipMutagens( p );
	report.pointsLeft = levelManager.GetPointsFree( ESkillPoint );
	return true;
}

// Buys the preset's tree back, one level at a time. Skills are tried in ascending order of
// the points their tier requires, and passes repeat until nothing more can be bought, so
// tier thresholds and skill dependencies (Remastered tree) are met in any order.
// Returns the number of levels that could not be bought.
@addMethod(W3PlayerWitcher) function TspRebuyTree( p : CTspPreset ) : int
{
	var order : array< int >;
	var tiers : array< int >;
	var sk : SSkill;
	var skill : ESkill;
	var target, before, missing, i, j, tmp : int;
	var progress : bool;

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
			while ( TspBoughtLevel( skill ) < target && CanLearnSkill( skill ) && HasSpentEnoughPoints( skill ) )
			{
				before = TspBoughtLevel( skill );
				AddSkill( skill );
				if ( TspBoughtLevel( skill ) <= before )
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
		missing += Max( 0, target - TspBoughtLevel( skill ) );
	}
	return missing;
}

// level actually bought (W3PlayerWitcher.GetSkillLevel can include bonuses)
@addMethod(W3PlayerWitcher) function TspBoughtLevel( skill : ESkill ) : int
{
	return ( (W3PlayerAbilityManager)abilityManager ).GetBoughtSkillLevel( skill );
}

// returns the number of saved skills that could not be put back in their slot
@addMethod(W3PlayerWitcher) function TspEquipSlots( p : CTspPreset ) : int
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
@addMethod(W3PlayerWitcher) function TspEquipMutagens( p : CTspPreset ) : int
{
	var pam : W3PlayerAbilityManager;
	var item : SItemUniqueId;
	var missing, i : int;

	pam = (W3PlayerAbilityManager)abilityManager;
	for ( i = 0; i < p.mutagenSlots.Size(); i += 1 )
	{
		if ( pam.IsSkillMutagenSlotUnlocked( p.mutagenSlots[ i ] )
			&& TspFindFreeItem( p.mutagenNames[ i ], item )
			&& EquipItemInGivenSlot( item, p.mutagenSlots[ i ], false ) )
		{
			continue;
		}
		missing += 1;
	}
	return missing;
}

// an unequipped inventory item with this name
@addMethod(W3PlayerWitcher) function TspFindFreeItem( itemName : name, out item : SItemUniqueId ) : bool
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
@addMethod(W3PlayerWitcher) function TspPresetCost( p : CTspPreset ) : int
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
@addMethod(W3PlayerWitcher) function TspTreePointsAvailable() : int
{
	return levelManager.GetPointsFree( ESkillPoint ) + levelManager.GetPointsUsed( ESkillPoint )
		- ( (W3PlayerAbilityManager)abilityManager ).GetMutationsUsedSkillPoints();
}

// refunds every tree point without a potion; the current build goes to the undo slot
@addMethod(W3PlayerWitcher) function TspResetTree() : bool
{
	if ( IsInCombat() )
	{
		return false;
	}
	TspSave( TspUndoIndex() );
	ResetCharacterDev();
	return true;
}

// ---- character menu refresh ----
// The skills screen caches what it shows; after a change made outside of it (console),
// redraw it the same way it redraws itself after buying or equipping a skill.

@addMethod(CR4CharacterDupeMenu) function TspRefresh()
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

@addMethod(CR4CharacterMenu) function TspRefresh()
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

// redraws the skills screen if it is the menu currently shown
function TspRefreshCharacterMenu()
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
		dupe.TspRefresh();
		return;
	}
	legacy = (CR4CharacterMenu)last;
	if ( legacy )
	{
		legacy.TspRefresh();
	}
}

// ---- notifications ----

function TspNotify( msg : string )
{
	theGame.GetGuiManager().ShowNotification( msg, 6000 );
}

function TspReportText( report : STspLoadReport ) : string
{
	var msg : string;

	if ( report.missingLevels > 0 )
	{
		msg += "<br>" + IntToString( report.missingLevels ) + " skill level(s) could not be bought";
	}
	if ( report.mutationFailed )
	{
		msg += "<br>Mutation could not be equipped";
	}
	msg += "<br>Slotted skills: " + IntToString( report.savedSlots - report.missingSlots )
		+ " / " + IntToString( report.savedSlots );
	if ( report.missingMutagens > 0 )
	{
		msg += "<br>" + IntToString( report.missingMutagens ) + " mutagen(s) missing";
	}
	msg += "<br>Free skill points: " + IntToString( report.pointsLeft );
	return msg;
}

function TspValidIndex( n : int ) : bool
{
	if ( n < 1 || n > TspPresetCount() )
	{
		TspNotify( "Preset number must be 1.." + IntToString( TspPresetCount() ) );
		return false;
	}
	return true;
}

function TspLoadAndNotify( idx : int )
{
	var w : W3PlayerWitcher;
	var report : STspLoadReport;

	w = GetWitcherPlayer();
	if ( w.IsInCombat() )
	{
		TspNotify( GetLocStringByKeyExt( "menu_cannot_perform_action_combat" ) );
		return;
	}
	if ( !w.TspLoad( idx, report ) )
	{
		TspNotify( w.TspGetData().DisplayName( idx ) + " is empty" );
		return;
	}
	TspRefreshCharacterMenu();
	TspNotify( w.TspGetData().DisplayName( idx ) + " loaded" + TspReportText( report ) );
}

// ---- debug console ----

exec function tsp_save( n : int )
{
	var w : W3PlayerWitcher;
	var p : CTspPreset;

	w = GetWitcherPlayer();
	if ( !TspValidIndex( n ) )
	{
		return;
	}
	if ( w.IsInCombat() )
	{
		TspNotify( GetLocStringByKeyExt( "menu_cannot_perform_action_combat" ) );
		return;
	}
	if ( w.TspSave( n - 1 ) )
	{
		p = w.TspGetData().Get( n - 1 );
		TspNotify( w.TspGetData().DisplayName( n - 1 ) + " saved ("
			+ IntToString( p.treeSkills.Size() ) + " skills, "
			+ IntToString( w.TspPresetCost( p ) ) + " points)"
			+ "<br>Slotted skills: " + IntToString( p.slotIds.Size() )
			+ "<br>Mutagens: " + IntToString( p.mutagenSlots.Size() ) );
	}
}

exec function tsp_load( n : int )
{
	if ( TspValidIndex( n ) )
	{
		TspLoadAndNotify( n - 1 );
	}
}

// refunds all tree points (like a Potion of Clearance, none used); tsp_undo restores
exec function tsp_reset()
{
	var w : W3PlayerWitcher;

	w = GetWitcherPlayer();
	if ( !w.TspResetTree() )
	{
		TspNotify( GetLocStringByKeyExt( "menu_cannot_perform_action_combat" ) );
		return;
	}
	TspRefreshCharacterMenu();
	TspNotify( "Skill tree reset<br>Free skill points: "
		+ IntToString( w.levelManager.GetPointsFree( ESkillPoint ) ) );
}

// reloads the build that was active before the last tsp_load / tsp_reset
exec function tsp_undo()
{
	TspLoadAndNotify( TspUndoIndex() );
}

exec function tsp_name( n : int, newName : string )
{
	var w : W3PlayerWitcher;
	var p : CTspPreset;

	w = GetWitcherPlayer();
	if ( TspValidIndex( n ) )
	{
		p = w.TspGetData().Get( n - 1 );
		p.label = StrLeft( newName, 24 );
		TspNotify( w.TspGetData().DisplayName( n - 1 ) );
	}
}

exec function tsp_info( n : int )
{
	var w : W3PlayerWitcher;
	var p : CTspPreset;
	var available : int;

	w = GetWitcherPlayer();
	if ( !TspValidIndex( n ) )
	{
		return;
	}
	p = w.TspGetData().Get( n - 1 );
	if ( !p.used )
	{
		TspNotify( w.TspGetData().DisplayName( n - 1 ) + " is empty" );
		return;
	}
	available = w.TspTreePointsAvailable();
	TspNotify( w.TspGetData().DisplayName( n - 1 )
		+ "<br>Tree skills: " + IntToString( p.treeSkills.Size() )
		+ "<br>Cost: " + IntToString( w.TspPresetCost( p ) ) + " / " + IntToString( available ) + " points"
		+ "<br>Slotted skills: " + IntToString( p.slotIds.Size() )
		+ "<br>Mutagens: " + IntToString( p.mutagenSlots.Size() ) );
}
