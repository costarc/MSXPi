"""PCheckers rooms on the pchess relay: moves are relayed as text, chat is
the pchess chat."""
import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import msxpi_pchess as p


class Room(unittest.TestCase):
    def setUp(self):
        self.g=p.Games()
        self.a=self.join()
        self.b=self.join()
    def join(self,room='dama'):
        return self.g.request(dict(action='new',mode='room',room=room,kind='checkers'))
    def act(self,who,action,**kw):
        return self.g.request(dict(action=action,game=who['game'],token=who['token'],**kw))
    def test_join_and_sides(self):
        self.assertEqual((self.a['side'],self.b['side']),(0,1))
        self.assertTrue(self.b['matched'])
        with self.assertRaises(ValueError): self.join()
    def test_chess_room_of_same_name_is_separate(self):
        c=self.g.request(dict(action='new',mode='room',room='dama'))
        self.assertNotEqual(c['game'],self.a['game'])
    def test_moves_alternate_and_poll(self):
        with self.assertRaises(ValueError): self.act(self.b,'cmove',ply=0,move='b6a5')
        self.act(self.a,'cmove',ply=0,move='c3d4')
        with self.assertRaises(ValueError): self.act(self.a,'cmove',ply=1,move='d4e5')
        with self.assertRaises(ValueError): self.act(self.b,'cmove',ply=0,move='b6a5')   # stale
        with self.assertRaises(ValueError): self.act(self.b,'cmove',ply=1,move='z9')
        self.act(self.b,'cmove',ply=1,move='d6e5')
        self.act(self.a,'cmove',ply=2,move='d4f6h8')
        state=self.act(self.b,'cpoll',ply=0)
        self.assertEqual(state['moves'],['c3d4','d6e5','d4f6h8'])
        self.assertEqual(self.act(self.b,'cpoll',ply=2)['moves'],['d4f6h8'])
    def test_packet(self):
        self.act(self.a,'cmove',ply=0,move='c3d4')
        data=p.checkers_packet(self.act(self.b,'cpoll',ply=0))
        self.assertEqual(data[:4],b'PCH1')
        self.assertEqual((data[4],data[5],data[6],data[7]),(1,1,1,0))
        # c3 = row 5 col 2 = 42, d4 = row 4 col 3 = 35
        self.assertEqual(tuple(data[120:123]),(2,42,35))
        self.assertEqual((data[240],data[241]),(1,1))
    def test_draw_resign_reset(self):
        self.assertEqual(self.act(self.a,'cdraw')['offer'],2)
        self.assertEqual(self.act(self.b,'cpoll',ply=0)['offer'],1)
        self.assertEqual(self.act(self.b,'cdraw')['over'],3)
        with self.assertRaises(ValueError): self.act(self.a,'cmove',ply=0,move='c3d4')
        self.act(self.a,'creset')
        self.act(self.a,'cmove',ply=0,move='c3d4')
        self.assertEqual(self.act(self.b,'cresign')['over'],1)   # black resigned
        self.assertEqual(self.act(self.a,'cpoll',ply=0)['over'],1)
    def test_moving_declines_draw(self):
        self.act(self.a,'cmove',ply=0,move='c3d4')
        self.assertEqual(self.act(self.b,'cdraw')['offer'],2)
        self.act(self.a,'cdraw')                       # agrees: both offered
        self.assertEqual(self.act(self.a,'cpoll',ply=0)['over'],3)
    def test_chat_is_shared_with_pchess(self):
        self.act(self.a,'say',text='ola, bom jogo')
        state=self.act(self.b,'chat')
        self.assertEqual(state['chat_rows'],[(1,'WHITE: OLA, BOM JOGO')])
        self.assertEqual(self.act(self.b,'cpoll',ply=0)['chat_unread'],0)
        self.act(self.b,'say',text='valeu')
        self.assertEqual(p.checkers_packet(self.act(self.a,'cpoll',ply=0))[255],1)
    def test_game_types_do_not_mix(self):
        with self.assertRaises(ValueError): self.act(self.a,'move',move='e4')
        c=self.g.request(dict(action='new',mode='room',room='xadrez'))
        with self.assertRaises(ValueError): self.act(c,'cmove',ply=0,move='c3d4')
    def test_checkers_need_a_room(self):
        with self.assertRaises(ValueError):
            self.g.request(dict(action='new',mode='local',kind='checkers'))


class Command(unittest.TestCase):
    def test_cjoin_through_handle_command(self):
        p._games=p.Games()
        with __import__('unittest.mock').mock.patch.object(p,'start_relay'):
            data=p.handle_command('cjoin dama2',room_config={})
        self.assertEqual(data[:4],b'PCH1')
        self.assertEqual(data[4],1)   # checkers state
        self.assertEqual(bytes(data[72:83]),b'WAIT PLAYER')


if __name__=='__main__':
    unittest.main()
