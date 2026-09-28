import sys
import unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import chess
import msxpi_pchess as p

class Rules(unittest.TestCase):
    def setUp(self):
        self.games=p.Games()
        self.state=self.games.request(dict(action='new',mode='local'))
    def move(self,move):
        return self.games.request(dict(action='move',game=self.state['game'],
                                  token=self.state['token'],move=move))
    def test_blocked_and_turn(self):
        for move in ('a1a4','e7e5','e2f3'):
            with self.assertRaises(ValueError): self.move(move)
        self.assertEqual(self.move('e4')['board'][36],'P')
        self.assertEqual(self.move('e7e5')['board'][28],'p')
    def test_mate(self):
        for move in ('f3','e5','g4','Qh4#'): state=self.move(move)
        self.assertEqual(state['status'],'BLACK WINS')
        with self.assertRaises(ValueError): self.move('a3')
    def test_castling(self):
        for move in ('e4','e5','Nf3','Nc6','Bc4','Nf6','O-O'): state=self.move(move)
        self.assertEqual(state['board'][62],'K')
        self.assertEqual(state['board'][61],'R')
    def test_en_passant(self):
        for move in ('e4','a6','e5','d5','exd6'): state=self.move(move)
        self.assertEqual(state['board'][27],'.')
        self.assertEqual(state['board'][19],'P')
    def test_underpromotion(self):
        self.games.games[self.state['game']]['board']=chess.Board('7k/P7/8/8/8/8/8/7K w - - 0 1')
        self.assertEqual(self.move('a7a8n')['board'][0],'N')
    def test_room(self):
        a=self.games.request(dict(action='new',mode='room',room='test'))
        b=self.games.request(dict(action='new',mode='room',room='test'))
        with self.assertRaises(ValueError):
            self.games.request(dict(action='move',game=b['game'],token=b['token'],move='e5'))
        state=self.games.request(dict(action='move',game=a['game'],token=a['token'],move='e4'))
        self.assertEqual(state['turn'],0)
        with self.assertRaises(ValueError): self.games.request(dict(action='new',mode='room',room='test'))
    def test_ai(self):
        a=self.games.request(dict(action='new',mode='ai'))
        state=self.games.request(dict(action='move',game=a['game'],token=a['token'],move='e4'))
        self.assertEqual(state['ply'],2)
        self.assertEqual(state['turn'],1)
        self.assertEqual(len(p.packet(state)),256)
    def test_errors_are_framed(self):
        data=p.handle_command('new invalid')
        self.assertEqual(data[:5],b'PCH1\0')
        self.assertEqual(len(data),256)

if __name__=='__main__': unittest.main()
