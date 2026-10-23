// Skill Tree Loadouts: pages of skill slots, every page active at once. The "Slot pages"
// option (1 to 5, src/config) sets how many; 1 = the game's slots only, no page buttons.
//
// Page 1 is the game's own 16 slots: skill slots 1..12 and the Blood and Wine mutation slots
// 13..16. Pages 2..5 add 12 skill slots each, ids 17..28, 29..40, 41..52, 53..64, appended to
// W3PlayerAbilityManager.skillSlots in id order (the skills screen relies on
// slot id = array index + 1, see CR4CharacterDupeMenu.tryUnequipSkill). The mutation slots
// are not paged: every page shows the game's 4, which keep all the game's rules.
// - skill slots of pages 2..5 unlock one after the other once page 1 is full: the first one
//   point after the last page 1 slot, then one more point each. They belong to no mutagen
//   group: only page 1 is linked to the mutagens;
// - lowering the option removes the last pages' slots and unequips their skills.
// A skill is active in any slot (W3PlayerAbilityManager.IsSkillEquipped), so all pages count.
//
// The skills screen draws 16 slots. While it reads them, GetSkillSlots returns the current
// page's 12 skill slots with the ids 1..12 it knows, plus the game's mutation slots 13..16;
// the slot ids it sends back (equip, unequip, buy, swap) are turned into real ids before the
// game code runs.

function StlPagesMax() : int
{
	return 5;
}

// true once StlPagesWanted wrote the option's default in this session (not saved)
@addField(CR4Game)
var stlPagesOptionWritten : bool;

// theGame is const: its fields are set from inside
@addMethod(CR4Game) function StlSetPagesOptionWritten()
{
	stlPagesOptionWritten = true;
}

// pages asked for in the options (Var StlSlotPages of the SkillTreeLoadouts group). The XML
// cannot give a slider a default: a value never set, or out of range, is written as 1 (or
// clamped) and saved, as the game does for its own settings (hud.ws, HasSeenDLCMessage).
// Written once per session at most: without the options file the value stays unset.
function StlPagesWanted() : int
{
	var config : CInGameConfigWrapper;
	var pages : int;

	config = theGame.GetInGameConfigWrapper();
	pages = RoundF( StringToFloat( config.GetVarValue( 'SkillTreeLoadouts', 'StlSlotPages' ), 0 ) );
	if ( pages < 1 || pages > StlPagesMax() )
	{
		pages = Clamp( pages, 1, StlPagesMax() );
		if ( !theGame.stlPagesOptionWritten )
		{
			theGame.StlSetPagesOptionWritten();
			config.SetVarValue( 'SkillTreeLoadouts', 'StlSlotPages', IntToString( pages ) );
			theGame.SaveUserSettings();
		}
	}
	return pages;
}

// skill slots of a page (page 1 also has the 4 mutation slots after them)
function StlPagesSkillSlots() : int
{
	return 12;
}

// skill points between two skill slots of pages 2..5 (one level each)
function StlPagesPointsPerSlot() : int
{
	return 1;
}

// unlockedOnLevel that 1.2.0 test builds gave to the mutation slots they added to every page:
// a save holding one still has that layout (see StlPagesApply)
function StlPagesOldLayoutMark() : int
{
	return 1000000;
}

// slots of the save for a number of pages
function StlPagesSlotTotal( pages : int ) : int
{
	return StlShownSlotCount() + ( pages - 1 ) * StlPagesSkillSlots();
}

// real id of a slot shown on the current page: the page's own skill slots for 1..12, the
// game's mutation slots for 13..16
function StlPagesRealSlotId( shownId : int ) : int
{
	if ( StlPageCount() < 2 || StlCurrentPage() == 1 || shownId < 1 || shownId > StlPagesSkillSlots() )
	{
		return shownId;
	}
	return StlPagesSlotTotal( StlCurrentPage() - 1 ) + shownId;
}

// ---- slots ----

// early in Init, before the skills are loaded: only adds slots (removing one unequips a skill)
@wrapMethod(W3PlayerAbilityManager) function InitSkillSlots( isFromLoad : bool )
{
	wrappedMethod( isFromLoad );
	StlPagesApply( false );
}

// Called when the skills screen opens and on level up: picks up a change of the option.
// The game then unlocks the slots the skill points allow.
@wrapMethod(W3PlayerAbilityManager) function UpdateSkillSlots()
{
	StlPagesApply( true );
	wrappedMethod();
}

// After the game set every slot's lock from the skill points: removes what the option no
// longer asks for, and empties the page slots that are locked.
@wrapMethod(W3PlayerAbilityManager) function PostInit()
{
	wrappedMethod();
	StlPagesApply( true );
	StlPagesDropLockedSkills();
}

// Gives the save the slots of the pages the option asks for: adds the missing ones, removes
// (and empties) the ones of pages above it when 'trim', and refreshes their settings.
@addMethod(W3PlayerAbilityManager) function StlPagesApply( trim : bool )
{
	var slot : SSkillSlot;
	var game, total, i, last, dropped : int;

	stlPageCount = 0;
	if ( !( (W3PlayerWitcher)owner ) )
	{
		return;
	}
	game = StlShownSlotCount();

	// a 1.2.0 test layout (mutation slots on every page): emptied and rebuilt, only once the
	// skills are loaded ('trim'); until then the pages stay off
	for ( i = game; i < skillSlots.Size(); i += 1 )
	{
		if ( skillSlots[ i ].unlockedOnLevel == StlPagesOldLayoutMark() )
		{
			if ( !trim )
			{
				return;
			}
			// not inside the log call: the release game drops logs with their arguments
			dropped = StlPagesTrim( game );
			LogChannel( 'STL', "old page layout: " + dropped + " skill(s) unequipped" );
			break;
		}
	}

	// page 1 must be the game's slots 1..16, and anything after them our slots, in id order,
	// by whole pages; another layout (another mod adding slots) leaves the pages off
	if ( skillSlots.Size() < game || skillSlots.Size() > StlPagesSlotTotal( StlPagesMax() )
		|| ( skillSlots.Size() - game ) % StlPagesSkillSlots() != 0 )
	{
		LogChannel( 'STL', "pages off: " + skillSlots.Size() + " skill slots" );
		return;
	}
	for ( i = 0; i < skillSlots.Size(); i += 1 )
	{
		if ( skillSlots[ i ].id != i + 1 )
		{
			LogChannel( 'STL', "pages off: slot " + i + " has id " + skillSlots[ i ].id );
			return;
		}
	}

	total = StlPagesSlotTotal( StlPagesWanted() );
	if ( trim )
	{
		StlPagesTrim( total );
	}

	slot.socketedSkill = S_SUndefined;
	slot.unlocked = false;
	slot.groupID = -1;
	for ( i = skillSlots.Size(); i < total; i += 1 )
	{
		slot.id = i + 1;
		skillSlots.PushBack( slot );
	}

	// thresholds continue after the last page 1 skill slot (read again at each start, in case
	// the game changes page 1's)
	for ( i = 0; i < StlPagesSkillSlots(); i += 1 )
	{
		last = Max( last, skillSlots[ i ].unlockedOnLevel );
	}
	for ( i = game; i < skillSlots.Size(); i += 1 )
	{
		skillSlots[ i ].groupID = -1;
		skillSlots[ i ].unlockedOnLevel = last + ( i - game + 1 ) * StlPagesPointsPerSlot();
	}

	// ids are 1..Size() (checked above): GetSkillOnSlot and GetFreeSkillSlot go up to it
	totalSkillSlotsCount = skillSlots.Size();
	stlPageCount = 1 + ( skillSlots.Size() - game ) / StlPagesSkillSlots();
}

// Removes the slots after the first 'keep' ones (pages 2..5 only), unequipping their skills
// the way UnequipSkill does. Returns the skills unequipped.
@addMethod(W3PlayerAbilityManager) function StlPagesTrim( keep : int ) : int
{
	var skill : ESkill;
	var i, count : int;

	for ( i = skillSlots.Size() - 1; i >= Max( keep, StlShownSlotCount() ); i -= 1 )
	{
		skill = skillSlots[ i ].socketedSkill;
		if ( skill != S_SUndefined )
		{
			skillSlots[ i ].socketedSkill = S_SUndefined;
			OnSkillUnequip( skill );
			count += 1;
		}
		skillSlots.Erase( i );
	}
	return count;
}

// Empties the skill slots of pages 2..5 that are locked: a skill stays active in any slot,
// locked or not (IsSkillEquipped), e.g. after the thresholds changed in a save.
@addMethod(W3PlayerAbilityManager) function StlPagesDropLockedSkills()
{
	var skill : ESkill;
	var i : int;

	if ( stlPageCount < 2 )
	{
		return;
	}
	for ( i = StlShownSlotCount(); i < skillSlots.Size(); i += 1 )
	{
		skill = skillSlots[ i ].socketedSkill;
		if ( !skillSlots[ i ].unlocked && skill != S_SUndefined )
		{
			skillSlots[ i ].socketedSkill = S_SUndefined;
			OnSkillUnequip( skill );
		}
	}
}

// the slots of one page, with the ids 1..16 of the skills screen, while it reads them
@wrapMethod(W3PlayerAbilityManager) function GetSkillSlots() : array< SSkillSlot >
{
	var all : array< SSkillSlot >;
	var view : array< SSkillSlot >;
	var slot : SSkillSlot;
	var first, i : int;

	all = wrappedMethod();
	if ( stlViewPage < 2 || stlPageCount < 2 )
	{
		if ( stlViewPage < 1 || stlPageCount < 1 )
		{
			return all;
		}
		// page 1: the game's 16 slots only
		for ( i = 0; i < StlShownSlotCount() && i < all.Size(); i += 1 )
		{
			view.PushBack( all[ i ] );
		}
		return view;
	}
	first = StlPagesSlotTotal( stlViewPage - 1 );
	for ( i = 0; i < StlPagesSkillSlots() && first + i < all.Size(); i += 1 )
	{
		slot = all[ first + i ];
		slot.id = i + 1;
		view.PushBack( slot );
	}
	// the game's mutation slots, ids 13..16 already
	for ( i = StlPagesSkillSlots(); i < StlShownSlotCount() && i < all.Size(); i += 1 )
	{
		view.PushBack( all[ i ] );
	}
	return view;
}

// Empties pages 2..5 and removes their slots from the save. Returns the skills unequipped.
@addMethod(W3PlayerAbilityManager) function StlPagesRemove() : int
{
	var count : int;

	count = StlPagesTrim( StlShownSlotCount() );
	totalSkillSlotsCount = skillSlots.Size();
	stlPageCount = 0;
	return count;
}

// ---- skills screen ----

@addMethod(CR4CharacterDupeMenu) function StlPagesView( on : bool )
{
	var pam : W3PlayerAbilityManager;

	pam = (W3PlayerAbilityManager)GetWitcherPlayer().abilityManager;
	if ( !pam )
	{
		return;
	}
	if ( on && pam.stlPageCount > 0 )
	{
		pam.stlViewPage = StlCurrentPage();
	}
	else
	{
		pam.stlViewPage = 0;
	}
}

// After an action on a page other than 1, the game updated the real slot ids, which the
// screen does not have: draw the whole page again.
@addMethod(CR4CharacterDupeMenu) function StlPagesRedraw()
{
	var i : int;

	if ( StlPageCount() < 2 || StlCurrentPage() == 1 )
	{
		return;
	}
	for ( i = 1; i <= StlShownSlotCount(); i += 1 )
	{
		m_fxClearSkillSlot.InvokeSelfOneArg( FlashArgInt( i ) );
	}
	UpdateAppliedSkills();
}

@wrapMethod(CR4CharacterDupeMenu) function UpdateAppliedSkills()
{
	StlPagesView( true );
	wrappedMethod();
	StlPagesView( false );
}

@wrapMethod(CR4CharacterDupeMenu) function UpdateAppliedSkillIfEquipped( skill : ESkill )
{
	StlPagesView( true );
	wrappedMethod( skill );
	StlPagesView( false );
}

@wrapMethod(CR4CharacterDupeMenu) function OnEquipSkill( skill : ESkill, slotID : int )
{
	var ret : bool;

	ret = wrappedMethod( skill, StlPagesRealSlotId( slotID ) );
	StlPagesRedraw();
	return ret;
}

@wrapMethod(CR4CharacterDupeMenu) function OnUnequipSkill( slotID : int )
{
	var ret : bool;

	ret = wrappedMethod( StlPagesRealSlotId( slotID ) );
	StlPagesRedraw();
	return ret;
}

@wrapMethod(CR4CharacterDupeMenu) function OnBuySkill( skill : ESkill, slotID : int )
{
	var ret : bool;

	ret = wrappedMethod( skill, StlPagesRealSlotId( slotID ) );
	StlPagesRedraw();
	return ret;
}

@wrapMethod(CR4CharacterDupeMenu) function OnSwapSkill( skill1 : ESkill, slotID1 : int, skill2 : ESkill, slotID2 : int )
{
	var ret : bool;

	ret = wrappedMethod( skill1, StlPagesRealSlotId( slotID1 ), skill2, StlPagesRealSlotId( slotID2 ) );
	StlPagesRedraw();
	return ret;
}

// ---- debug console ----

// state of the slot pages, to diagnose a problem
@addMethod(W3PlayerAbilityManager) function StlPagesInfo() : string
{
	var config : CInGameConfigWrapper;
	var msg : string;
	var i : int;

	config = theGame.GetInGameConfigWrapper();
	msg = "option '" + config.GetVarValue( 'SkillTreeLoadouts', 'StlSlotPages' ) + "' -> " + StlPagesWanted()
		+ "<br>slots " + skillSlots.Size() + ", pages " + stlPageCount + ", max id " + totalSkillSlotsCount;
	for ( i = 0; i < skillSlots.Size(); i += 1 )
	{
		if ( skillSlots[ i ].id != i + 1 )
		{
			msg += "<br>layout: slot " + i + " has id " + skillSlots[ i ].id;
			break;
		}
	}
	for ( i = StlShownSlotCount(); i < skillSlots.Size(); i += 1 )
	{
		if ( skillSlots[ i ].socketedSkill != S_SUndefined )
		{
			msg += "<br>slot " + skillSlots[ i ].id + ": " + StlSkillDisplayName( skillSlots[ i ].socketedSkill );
		}
	}
	return msg;
}

exec function stl_pages_info()
{
	var w : W3PlayerWitcher;

	w = GetWitcherPlayer();
	if ( w )
	{
		StlNotify( ( (W3PlayerAbilityManager)w.abilityManager ).StlPagesInfo() );
	}
}

// empties and removes pages 2..5 now; they come back at the next level up or skills screen
// if the option still asks for them
exec function stl_pages_remove()
{
	var w : W3PlayerWitcher;
	var pam : W3PlayerAbilityManager;
	var count : int;

	w = GetWitcherPlayer();
	if ( !w )
	{
		return;
	}
	pam = (W3PlayerAbilityManager)w.abilityManager;
	count = pam.StlPagesRemove();
	w.stlPage = 1;
	StlRefreshCharacterMenu();
	StlNotify( StlLocF( "stl_pages_removed", "Slot pages 2 to 5 removed, $0$ skill(s) unequipped. Save the game, then uninstall the mod.",
		IntToString( count ) ) );
}
