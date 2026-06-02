import React from 'react';
import { TabBar } from './TabBar';
import { Gamepad2, Grid3X3, HelpCircle, Link2, Target, Component } from 'lucide-react';

export function GamesScreen() {
  const games = [
    { id: 1, title: 'Chess', desc: 'A game of strategy', icon: Component },
    { id: 2, title: 'Battleship', desc: 'Sink the fleet', icon: Target },
    { id: 3, title: 'Tic-Tac-Toe', desc: 'Classic, now at 30,000 feet', icon: Grid3X3 },
    { id: 4, title: 'Trivia', desc: 'Test your knowledge against the cabin', icon: HelpCircle },
    { id: 5, title: 'Word Chain', desc: 'Keep the chain going or lose', icon: Link2 },
  ];

  return (
    <div className="w-full h-full pt-[60px] pb-[100px] flex flex-col relative px-[24px]">
      <h1 className="text-[24px] font-medium tracking-tight text-text-primary mb-8 shrink-0">Games</h1>

      <div className="flex flex-col gap-3 flex-1 overflow-y-auto">
        {games.map((game) => {
          const Icon = game.icon;
          return (
            <div 
              key={game.id} 
              className="flex items-center p-4 rounded-[16px] bg-surface border border-border-subtle"
            >
              <div className="w-[40px] h-[40px] rounded-full flex items-center justify-center shrink-0 mr-4 bg-surface-raised border border-border-subtle">
                <Icon size={18} className="text-text-primary" strokeWidth={1.5} />
              </div>
              
              <div className="flex-1 min-w-0 pr-4">
                <h3 className="text-[15px] font-medium text-text-primary mb-0.5 truncate">{game.title}</h3>
                <p className="text-[13px] text-text-muted truncate">{game.desc}</p>
              </div>
            </div>
          );
        })}
      </div>

      <TabBar activeTab="games" />
    </div>
  );
}
