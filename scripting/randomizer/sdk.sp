static Handle g_hSDKGetMaxHealth;
static Handle g_hSDKRemoveWearable;
static Handle g_hSDKEquipWearable;
static Handle g_hSDKGetMaxAmmo;
static Handle g_hSDKDoClassSpecialSkill;
static Handle g_hSDKGetBaseEntity;

static Handle g_hDHookSecondaryAttack;

static int g_iOffsetItemDefinitionIndex = -1;
static Address g_pPlayerSharedOuter;

static bool g_bDoClassSpecialSkill[TF_MAXPLAYERS+1];

public void SDK_Init()
{
	GameData hGameData = new GameData("sdkhooks.games");
	if (!hGameData)
		SetFailState("Could not find sdkhooks.games gamedata");
	
	//Max health
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "GetMaxHealth");
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hSDKGetMaxHealth = EndPrepSDKCall();
	if(!g_hSDKGetMaxHealth)
		LogError("Failed to create call: CTFPlayer::GetMaxHealth");
	
	delete hGameData;
	
	hGameData = new GameData("sm-tf2.games");
	if (!hGameData)
		SetFailState("Could not find sm-tf2.games gamedata");
	
	int iRemoveWearableOffset = hGameData.GetOffset("RemoveWearable");
	
	//Remove Wearable
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetVirtual(iRemoveWearableOffset);
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSDKRemoveWearable = EndPrepSDKCall();
	if (!g_hSDKRemoveWearable)
		LogError("Failed to create call: CBasePlayer::RemoveWearable");
	
	//Equip Wearable
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetVirtual(iRemoveWearableOffset-1);//Equip Wearable is right behind Remove Wearable, should be good if valve dont add one between
	PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSDKEquipWearable = EndPrepSDKCall();
	if (!g_hSDKEquipWearable)
		LogError("Failed to create call: CBasePlayer::EquipWearable");
	
	delete hGameData;
	
	hGameData = new GameData("randomizer");
	if (!hGameData)
		SetFailState("Could not find randomizer gamedata");
	
	//Get Max Ammo
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTFPlayer::GetMaxAmmo");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	g_hSDKGetMaxAmmo = EndPrepSDKCall();
	if (!g_hSDKGetMaxAmmo)
		LogError("Failed to create call: CTFPlayer::GetMaxAmmo");
	
	StartPrepSDKCall(SDKCall_Player);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CTFPlayer::DoClassSpecialSkill");
	PrepSDKCall_SetReturnInfo(SDKType_Bool, SDKPass_Plain);
	g_hSDKDoClassSpecialSkill = EndPrepSDKCall();
	if (!g_hSDKDoClassSpecialSkill)
		LogError("Failed to create call: CTFPlayer::DoClassSpecialSkill");
	
	SDK_CreateDetour(hGameData, "CTFPlayer::GetMaxAmmo", DHook_GetMaxAmmoPre, _);
	SDK_CreateDetour(hGameData, "CTFPlayer::Taunt", DHook_TauntPre, DHook_TauntPost);
	SDK_CreateDetour(hGameData, "CTFPlayer::CanAirDash", _, DHook_CanAirDashPost);
	SDK_CreateDetour(hGameData, "CTFPlayer::ItemsMatch", DHook_ItemsMatchPre, _);
	SDK_CreateDetour(hGameData, "CTFPlayer::OnDealtDamage", DHook_OnDealtDamagePre, DHook_OnDealtDamagePost);
	SDK_CreateDetour(hGameData, "CTFPlayer::DoClassSpecialSkill", DHook_DoClassSpecialSkillPre, DHook_DoClassSpecialSkillPost);
	SDK_CreateDetour(hGameData, "CTFPlayerShared::UpdateItemChargeMeters", DHook_UpdateItemChargeMetersPre, DHook_UpdateItemChargeMetersPost);
	SDK_CreateDetour(hGameData, "CTFPlayerShared::UpdateChargeMeter", DHook_UpdateChargeMeterPre, DHook_UpdateChargeMeterPost);
	
	g_hDHookSecondaryAttack = DHookCreateFromConf(hGameData, "CBaseCombatWeapon::SecondaryAttack");
	if (!g_hDHookSecondaryAttack)
		LogError("Failed to create hook: CBaseCombatWeapon::SecondaryAttack");
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "CBaseEntity::GetBaseEntity");
	PrepSDKCall_SetReturnInfo(SDKType_CBaseEntity, SDKPass_Pointer);
	g_hSDKGetBaseEntity = EndPrepSDKCall();
	if (!g_hSDKGetBaseEntity)
		LogError("Failed to create call: CBaseEntity::GetBaseEntity");
	
	g_pPlayerSharedOuter = view_as<Address>(hGameData.GetOffset("CTFPlayerShared::m_pOuter"));
	g_iOffsetItemDefinitionIndex = hGameData.GetOffset("CEconItemView::m_iItemDefinitionIndex");
	
	delete hGameData;
}

static void SDK_CreateDetour(GameData hGameData, const char[] sName, DHookCallback preCallback = INVALID_FUNCTION, DHookCallback postCallback = INVALID_FUNCTION)
{
	Handle hDetour = DHookCreateFromConf(hGameData, sName);
	if (!hDetour)
	{
		LogError("Failed to create detour: %s", sName);
	}
	else
	{
		if (preCallback != INVALID_FUNCTION)
			if (!DHookEnableDetour(hDetour, false, preCallback))
				LogError("Failed to enable pre detour: %s", sName);
		
		if (postCallback != INVALID_FUNCTION)
			if (!DHookEnableDetour(hDetour, true, postCallback))
				LogError("Failed to enable post detour: %s", sName);
		
		delete hDetour;
	}
}

void SDK_HookWeapon(int iWeapon)
{
	DHookEntity(g_hDHookSecondaryAttack, false, iWeapon, _, DHook_SecondaryWeaponPre);
	DHookEntity(g_hDHookSecondaryAttack, true, iWeapon, _, DHook_SecondaryWeaponPost);
	
	SDKHook(iWeapon, SDKHook_ReloadPost, Hook_ReloadPost);
}

stock int SDK_GetMaxHealth(int iClient)
{
	if (g_hSDKGetMaxHealth)
		return SDKCall(g_hSDKGetMaxHealth, iClient);
	
	return 0;
}

stock void SDK_RemoveWearable(int iClient, int iWearable)
{
	if (g_hSDKRemoveWearable)
		SDKCall(g_hSDKRemoveWearable, iClient, iWearable);
}

stock void SDK_EquipWearable(int iClient, int iWearable)
{
	if (g_hSDKEquipWearable)
		SDKCall(g_hSDKEquipWearable, iClient, iWearable);
}

stock int SDK_GetMaxAmmo(int iClient, int iAmmoType)
{
	if (g_hSDKGetMaxAmmo)
		return SDKCall(g_hSDKGetMaxAmmo, iClient, iAmmoType, -1);
	
	return -1;
}

stock bool SDK_DoClassSpecialSkill(int iClient)
{
	if (g_hSDKDoClassSpecialSkill)
		return SDKCall(g_hSDKDoClassSpecialSkill, iClient);
	
	return false;
}

public MRESReturn DHook_GetMaxAmmoPre(int iClient, Handle hReturn, Handle hParams)
{
	int iAmmoType = DHookGetParam(hParams, 1);
	TFClassType nClass = DHookGetParam(hParams, 2);
	
	if (nClass != view_as<TFClassType>(-1))
		return MRES_Ignored;
	
	if (iAmmoType == TF_AMMO_METAL)
	{
		//Metal works differently, engineer have max metal 200 while others have 100
		DHookSetParam(hParams, 2, TFClass_Engineer);
		return MRES_ChangedHandled;
	}
	
	//By default iClassNumber returns -1, which would get client's class instead of given iClassNumber.
	//However using client's class can cause max ammo calculate to be incorrect,
	//We want to set iClassNumber to whatever class would normaly use weapon from iAmmoIndex.
	//TODO check shortstop's max ammo
	int iWeapon = TF2_GetItemFromAmmoType(iClient, iAmmoType);
	if (iWeapon <= MaxClients)
		return MRES_Ignored;
	
	TFClassType nDefaultClass = TF2_GetDefaultClassFromItem(iClient, iWeapon);
	DHookSetParam(hParams, 2, nDefaultClass);
	return MRES_ChangedHandled;
}

public MRESReturn DHook_TauntPre(int iClient, Handle hParams)
{
	//Player wants to taunt, set class to whoever can actually taunt with active weapon
	
	int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
	if (iWeapon <= MaxClients)
		return;
	
	TFClassType nClass = TF2_GetDefaultClassFromItem(iClient, iWeapon);
	if (nClass != TFClass_Unknown)
		TF2_SetPlayerClass(iClient, nClass);
}

public MRESReturn DHook_TauntPost(int iClient, Handle hParams)
{
	//Set class back to what it was
	TF2_SetPlayerClass(iClient, g_iClientClass[iClient]);
}

public MRESReturn DHook_CanAirDashPost(int iClient, Handle hReturn)
{
	//Atomizer's extra jumps does not work for non-scouts, fix that
	if (!DHookGetReturn(hReturn))
	{
		int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		
		float flVal;
		if (!TF2_WeaponFindAttribute(iWeapon, ATTRIB_AIR_DASH_COUNT, flVal))
			return MRES_Ignored;
		
		int iAirDash = GetEntProp(iClient, Prop_Send, "m_iAirDash");
		if (iAirDash < RoundToNearest(flVal))
		{
			SetEntProp(iClient, Prop_Send, "m_iAirDash", iAirDash + 1);
			DHookSetReturn(hReturn, true);
			return MRES_Supercede;
		}
	}
	
	return MRES_Ignored;
}

public MRESReturn DHook_ItemsMatchPre(int iClient, Handle hReturn, Handle hParams)
{
	if (g_iOffsetItemDefinitionIndex == -1)
		return MRES_Ignored;
	
	if (DHookIsNullParam(hParams, 2))
		return MRES_Ignored;
	
	//We want to prevent TF2 deleting weapons generated from randomizer and use player's TF2 loadout
	int iIndex1 = DHookGetParamObjectPtrVar(hParams, 2, g_iOffsetItemDefinitionIndex, ObjectValueType_Int) & 0xFFFF;
	
	//Try find slot, may be a problem for multi-class weapon
	int iSlot = -1;
	if (!DHookIsNullParam(hParams, 4))
	{
		int iWeapon = DHookGetParam(hParams, 4);
		iSlot = TF2_GetSlotFromItem(iClient, iWeapon);
	}
	
	if (iSlot < 0)
	{
		for (int iClass = CLASS_MIN; iClass <= CLASS_MAX; iClass++)
		{
			int iClassSlot = TF2_GetSlotFromIndex(iIndex1, view_as<TFClassType>(iClass));
			if (iClassSlot >= 0)
			{
				iSlot = iClassSlot;
				break;
			}
		}
	}
	
	if (iSlot < 0 || iSlot > WeaponSlot_BuilderEngie)
		return MRES_Ignored;
	
	//Get index we want to use from randomizer
	int iIndex2 = g_iClientWeaponIndex[iClient][iSlot];
	if (iIndex2 < 0)
	{
		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}
	
	//Set return whenever if index to give is same as what we wanted in randomizer
	DHookSetReturn(hReturn, iIndex1 == iIndex2);
	return MRES_Supercede;
}

public MRESReturn DHook_OnDealtDamagePre(int iClient, Handle hParams)
{
	//Gas Passer meter have hardcode pyro check in this call
	TF2_SetPlayerClass(iClient, TFClass_Pyro);
}

public MRESReturn DHook_OnDealtDamagePost(int iClient, Handle hParams)
{
	TF2_SetPlayerClass(iClient, g_iClientClass[iClient]);
}

public MRESReturn DHook_DoClassSpecialSkillPre(int iClient, Handle hReturn)
{
	//There 3 things going on in this function depending on player class attempting to:
	//If Demoman, detonate stickies or charge
	//If Engineer, pickup buildings
	//If Spy, cloak or uncloak
	//
	//We want to prevent Engineer and Spy stuffs from reload,
	//and allow demoman stuffs only if holding reload, not from attack2
	
	g_bDoClassSpecialSkill[iClient] = true;
	int iButtons = GetClientButtons(iClient);
	if (iButtons & IN_ATTACK2)
	{
		//Check if active weapon does something with attack2, if so prevent call
		int iWeapon = GetEntPropEnt(iClient, Prop_Send, "m_hActiveWeapon");
		if (iWeapon > MaxClients && Config_IsUsingAttack2(iWeapon))
		{
			DHookSetReturn(hReturn, false);
			return MRES_Supercede;
		}
	}
	
	int iSecondary = TF2_GetItemInSlot(iClient, WeaponSlot_Secondary);
	if (iSecondary > MaxClients)
	{
		TFClassType nDefaultClass = TF2_GetDefaultClassFromItem(iClient, iSecondary);
		if (nDefaultClass == TFClass_DemoMan)
		{
			if (iButtons & IN_RELOAD)
			{
				//Change class to allow detonate/charge from reload
				TF2_SetPlayerClass(iClient, TFClass_DemoMan);
				return MRES_Ignored;
			}
			else if (TF2_GetPlayerClass(iClient) == TFClass_DemoMan)
			{
				//If not holding reload and player is already demoman, prevent detonate/charge
				DHookSetReturn(hReturn, false);
				return MRES_Supercede;
			}
		}
	}
	
	if (iButtons & IN_RELOAD && !(iButtons & IN_ATTACK2))
	{
		//Nothing fancy need to do from SDK_DoClassSpecialSkill reload, prevent call
		DHookSetReturn(hReturn, false);
		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

public MRESReturn DHook_DoClassSpecialSkillPost(int iClient, Handle hReturn)
{
	TF2_SetPlayerClass(iClient, g_iClientClass[iClient]);
}

public MRESReturn DHook_UpdateItemChargeMetersPre(Address pPlayerShared)
{
	//Dragon Fury and Gas Passer meter have hardcode pyro check in this call
	int iClient = GetClientFromPlayerShared(pPlayerShared);
	TF2_SetPlayerClass(iClient, TFClass_Pyro);
}

public MRESReturn DHook_UpdateItemChargeMetersPost(Address pPlayerShared)
{
	int iClient = GetClientFromPlayerShared(pPlayerShared);
	TF2_SetPlayerClass(iClient, g_iClientClass[iClient]);
}

public MRESReturn DHook_UpdateChargeMeterPre(Address pPlayerShared)
{
	//This function is only used to manage demoshield meter, but have hardcode demoman class
	int iClient = GetClientFromPlayerShared(pPlayerShared);
	TF2_SetPlayerClass(iClient, TFClass_DemoMan);
}

public MRESReturn DHook_UpdateChargeMeterPost(Address pPlayerShared)
{
	int iClient = GetClientFromPlayerShared(pPlayerShared);
	TF2_SetPlayerClass(iClient, g_iClientClass[iClient]);
}

public MRESReturn DHook_SecondaryWeaponPre(int iWeapon)
{
	//Prevent this called if stickybomb, moved to reload
	char sClassname[64];
	GetEntityClassname(iWeapon, sClassname, sizeof(sClassname));
	if (StrEqual(sClassname, "tf_weapon_pipebomblauncher"))
		return MRES_Supercede;
	
	int iClient = GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity");
	g_bDoClassSpecialSkill[iClient] = false;
	return MRES_Ignored;
}

public MRESReturn DHook_SecondaryWeaponPost(int iWeapon)
{
	int iClient = GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity");
	
	//If DoClassSpecialSkill not called during secondary attack, do it anyway lol
	if (!g_bDoClassSpecialSkill[iClient])
		SDK_DoClassSpecialSkill(iClient);
	
	g_bDoClassSpecialSkill[iClient] = false;
}

public void Hook_ReloadPost(int iWeapon, bool bResult)
{
	//Call DoClassSpecialSkill for detour to manage with stickybomb and charging
	int iClient = GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity");
	SDK_DoClassSpecialSkill(iClient);
}

static int GetClientFromPlayerShared(Address pPlayerShared)
{
	Address pEntity = view_as<Address>(LoadFromAddress(pPlayerShared + g_pPlayerSharedOuter, NumberType_Int32));
	return SDKCall(g_hSDKGetBaseEntity, pEntity);
}