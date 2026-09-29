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

class Engine(unittest.TestCase):
    """Stockfish integration, using a fake UCI engine that always plays e7e5."""
    def play(self,config):
        p._engine_config=config
        games=p.Games()
        a=games.request(dict(action='new',mode='ai'))
        return games.request(dict(action='move',game=a['game'],token=a['token'],move='e4'))
    def tearDown(self):
        if p._engine: p._engine.quit()
        p._engine=None; p._engine_config={}
    def fake(self,log):
        import tempfile,os
        script=Path(__file__).with_name('fake_uci_engine.py')
        wrapper=Path(tempfile.mkdtemp())/('fake.bat' if os.name=='nt' else 'fake.sh')
        if os.name=='nt': wrapper.write_text(f'@"{sys.executable}" "{script}" "{log}"\n')
        else:
            wrapper.write_text(f'#!/bin/sh\nexec "{sys.executable}" "{script}" "{log}"\n')
            wrapper.chmod(0o755)
        return str(wrapper)
    def test_low_elo_uses_skill_level(self):
        import tempfile
        log=Path(tempfile.mkdtemp())/'uci.log'
        state=self.play(dict(PCHESSENGINE=self.fake(log),PCHESSELO='800',PCHESSMOVETIME='0.1'))
        self.assertEqual(state['history'],['e4','e5'])
        text=log.read_text()
        self.assertIn('setoption name Skill Level value 0',text)
        self.assertIn('depth 1',text)
    def test_high_elo_uses_uci_elo(self):
        import tempfile
        log=Path(tempfile.mkdtemp())/'uci.log'
        self.play(dict(PCHESSENGINE=self.fake(log),PCHESSELO='1600',PCHESSMOVETIME='0.1'))
        text=log.read_text()
        self.assertIn('setoption name UCI_Elo value 1600',text)
        self.assertIn('setoption name UCI_LimitStrength value true',text)
    def test_resources_pinned_and_engine_stops(self):
        import tempfile
        log=Path(tempfile.mkdtemp())/'uci.log'
        self.play(dict(PCHESSENGINE=self.fake(log),PCHESSMOVETIME='0.1'))
        self.assertIsNotNone(p._engine)
        p.handle_command('new local')
        self.assertIsNone(p._engine)
        text=log.read_text()
        self.assertIn('setoption name Threads value 1',text)
        self.assertIn('setoption name Hash value 16',text)
        self.assertIn('quit',text)
    def test_missing_engine_falls_back(self):
        state=self.play(dict(PCHESSENGINE='/no/such/stockfish'))
        self.assertEqual(state['ply'],2)

class Level(unittest.TestCase):
    def test_level_packet(self):
        data=p.level_packet('1350')
        self.assertEqual(data[:5],b'PCH1\0')
        self.assertEqual(data[242],4)
        self.assertTrue(data[72:].startswith(b'AI LEVEL 4 ELO 1350'))
        self.assertEqual(p.elo_level(''),2)
        self.assertEqual(p.elo_level('3000'),8)
        self.assertEqual([p.elo_level(e) for e in p.LEVEL_ELO],list(range(1,9)))

if __name__=='__main__': unittest.main()
