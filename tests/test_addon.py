"""Run with a Lua 5.1 runtime: python -m pip install lupa==2.6."""
from pathlib import Path
import unittest
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
frames = {}; combat = false; counts = {[6265]=7, [5512]=1}
UIParent = { GetCenter = function() return 0,0 end }
DEFAULT_CHAT_FRAME = { AddMessage = function() end }
SlashCmdList = {}
function InCombatLockdown() return combat end
function UnitClass() return 'Warlock','WARLOCK' end
function GetSpellInfo(id) return 'Spell' .. id end
function GetItemCount(id) return counts[id] or 0 end
function GetBuildInfo() return 'unknown','0','',16001 end
function UnitGUID(unit) if unit=='player' then return 'Player-Warlock' end end
local methods = {}
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:SetAttribute(k,v)
 assert(not combat, 'Protected attributes changed in combat')
 self.attributes[k]=v
end
function methods:SetText(s) self.text=s end
function methods:GetCenter() return 0,0 end
function methods:IsShown() return not self.hidden end
function methods:Hide() self.hidden=true end
function methods:Show() self.hidden=false end
function methods:SetEnabled(value) self.enabled=value end
function methods:CreateFontString() return CreateFrame('FontString') end
function CreateFrame(kind,name,parent,template)
 local frame = {scripts={},attributes={},name=name,template=template}
 setmetatable(frame, {__index=function(_,k) return methods[k] or function() end end})
 table.insert(frames,frame)
 return frame
end
function event(name,...)
 frames[1].scripts.OnEvent(frames[1],name,...)
end
function findText(text)
 for _,f in ipairs(frames) do if f.text==text then return f end end
end
'''

class AddonTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(MOCK)
        for file in ('Queue.lua', 'Core.lua'):
            self.lua.execute((ROOT / 'WarlockServicesForever' / file).read_text())

    def test_queue_validation_deduplication_and_removal(self):
        self.lua.execute('''
        local q=WSFQueue.New()
        assert(not WSFQueue.Add(q,'Alice','please 123'))
        assert(not WSFQueue.Add(q,nil,'123'))
        assert(WSFQueue.Add(q,'Alice-Realm',' 123 '))
        assert(not WSFQueue.Add(q,'ALICE-REALM','123'))
        assert(WSFQueue.Add(q,'Bob','123'))
        assert(WSFQueue.Remove(q,1)=='Alice-Realm')
        assert(q.names[1]=='Bob')
        assert(WSFQueue.Add(q,'Alice-Realm','123'))
        ''')

    def test_login_requests_selection_and_combat(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        local summon=findText('Summon selected')
        assert(summon.attributes.macrotext=='')
        event('CHAT_MSG_PARTY','123','Alice-Realm')
        assert(summon.attributes.macrotext=='/targetexact Alice-Realm\\n/cast Spell698')
        combat=true
        event('CHAT_MSG_WHISPER','123','Bob')
        event('BAG_UPDATE')
        assert(summon.attributes.macrotext=='/targetexact Alice-Realm\\n/cast Spell698')
        combat=false
        event('PLAYER_REGEN_ENABLED')
        findText('Next').scripts.OnClick()
        assert(summon.attributes.macrotext=='/targetexact Bob\\n/cast Spell698')
        findText('Remove selected').scripts.OnClick()
        assert(summon.attributes.macrotext=='/targetexact Alice-Realm\\n/cast Spell698')
        SlashCmdList.WARLOCKSERVICESFOREVER('shards 20')
        assert(WarlockServicesForeverDB.shardTarget==20)
        SlashCmdList.WARLOCKSERVICESFOREVER('clear')
        assert(summon.attributes.macrotext=='')
        ''')

    def test_sender_cannot_inject_macro(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        event('CHAT_MSG_WHISPER','123','Eve\\n/cast Evil')
        assert(findText('Summon selected').attributes.macrotext=='')
        ''')

    def test_offer_stone_uses_empty_trade_slot(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        TradeFrame={IsShown=function() return true end}
        local cursor
        function GetCursorInfo() return cursor end
        function GetTradePlayerItemInfo(slot) if slot==1 then return 'Existing item' end end
        function GetContainerNumSlots(bag) return bag==0 and 1 or 0 end
        function GetContainerItemID() return 5512 end
        function PickupContainerItem() cursor='item' end
        function ClickTradeButton(slot) assert(slot==2); offered=true; cursor=nil end
        findText('Offer healthstone').scripts.OnClick()
        assert(offered)
        offered=false; combat=true
        findText('Offer healthstone').scripts.OnClick()
        assert(not offered)
        ''')

    def test_clickable_rows_target_and_select_requesters(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        event('CHAT_MSG_PARTY','123','Alice')
        event('CHAT_MSG_PARTY','123','Bob')
        local row=findText('Bob')
        assert(row.template=='SecureActionButtonTemplate,UIPanelButtonTemplate')
        assert(row.attributes.macrotext=='/targetexact Bob')
        row.scripts.PostClick(row)
        assert(findText('> Bob'))
        assert(findText('Summon selected').attributes.macrotext=='/targetexact Bob\\n/cast Spell698')
        combat=true
        findText('Alice').scripts.PostClick(findText('Alice'))
        assert(findText('Summon selected').attributes.macrotext=='/targetexact Bob\\n/cast Spell698')
        ''')

    def test_success_removes_recipient_not_current_selection(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        event('CHAT_MSG_PARTY','123','Alice-Realm')
        event('CHAT_MSG_PARTY','123','Bob')
        local bob=findText('Bob'); bob.scripts.PostClick(bob)
        -- The ritual starting, failing, and another caster's success must not remove Alice.
        local function log(kind,source,spell,dest)
            event('COMBAT_LOG_EVENT_UNFILTERED',0,kind,false,source,'Caster',0,0,
                'Player-Recipient',dest,0,0,spell)
        end
        log('SPELL_CAST_SUCCESS','Player-Warlock',698,'Alice')
        log('SPELL_CAST_FAILED','Player-Warlock',7720,'Alice')
        log('SPELL_SUMMON','Player-Other',7720,'Alice')
        assert(findText('Alice-Realm'):IsShown())
        log('SPELL_SUMMON','Player-Warlock',7720,'Alice')
        assert(findText('Summon selected').attributes.macrotext=='/targetexact Bob\\n/cast Spell698')
        local b=findText('> Bob'); assert(b:IsShown())
        log('SPELL_CAST_SUCCESS','Player-Warlock',7720,'Bob')
        assert(findText('Summon selected').attributes.macrotext=='')
        -- Removed requesters can request again.
        event('CHAT_MSG_PARTY','123','Bob')
        assert(findText('> Bob'):IsShown())
        ''')

    def test_modern_combat_log_and_deferred_completion(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        event('CHAT_MSG_PARTY','123','Alice')
        function CombatLogGetCurrentEventInfo()
            return 0,'SPELL_SUMMON',false,'Player-Warlock','Caster',0,0,
                'Player-Alice','Alice',0,0,7720
        end
        combat=true
        event('COMBAT_LOG_EVENT_UNFILTERED')
        assert(findText('Summon selected').attributes.macrotext~='')
        combat=false; event('PLAYER_REGEN_ENABLED')
        assert(findText('Summon selected').attributes.macrotext=='')
        ''')

    def test_paging_and_ambiguous_short_names(self):
        self.lua.execute('''
        event('PLAYER_LOGIN')
        for i=1,9 do event('CHAT_MSG_PARTY','123','Player'..i) end
        for i=1,8 do findText('Next').scripts.OnClick() end
        local row=findText('> Player9')
        assert(row and row:IsShown() and row.attributes.macrotext=='/targetexact Player9')
        SlashCmdList.WARLOCKSERVICESFOREVER('clear')
        event('CHAT_MSG_PARTY','123','Alice-One')
        event('CHAT_MSG_PARTY','123','Alice-Two')
        event('COMBAT_LOG_EVENT_UNFILTERED',0,'SPELL_SUMMON',false,
            'Player-Warlock','Caster',0,0,'Recipient','Alice',0,0,7720)
        assert(findText('> Alice-One'):IsShown())
        assert(findText('Alice-Two'):IsShown())
        ''')

    def test_other_classes_do_not_create_panel(self):
        self.lua.execute('''
        function UnitClass() return 'Mage','MAGE' end
        event('PLAYER_LOGIN')
        assert(#frames==1)
        SlashCmdList.WARLOCKSERVICESFOREVER('help')
        ''')

if __name__ == '__main__':
    unittest.main()
