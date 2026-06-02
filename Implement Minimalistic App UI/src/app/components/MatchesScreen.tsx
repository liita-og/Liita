import React from 'react';
import { TabBar } from './TabBar';
import { Avatar } from './Avatar';

export function MatchesScreen() {
  const matches = [
    { id: 1, name: 'Priya Mehta', initials: 'PM', seat: '14C', time: 'Matched 4 min ago', color: 0 },
    { id: 2, name: 'James Okafor', initials: 'JO', seat: '7B', time: 'Matched 11 min ago', color: 1 },
  ];

  return (
    <div className="w-full h-full pt-[60px] pb-[100px] flex flex-col relative px-[24px]">
      <div className="mb-10 shrink-0">
        <h1 className="text-[24px] font-medium tracking-tight text-text-primary">Matches</h1>
      </div>

      <div className="flex-1 overflow-y-auto flex flex-col gap-3">
        {matches.map((match) => (
          <div 
            key={match.id} 
            className="flex items-center p-3 rounded-[16px] bg-surface border border-border-subtle"
          >
            <Avatar initials={match.initials} size={48} colorIndex={match.color} />
            
            <div className="flex-1 min-w-0 pl-4">
              <div className="text-[15px] font-medium text-text-primary truncate mb-1">
                {match.name}
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[12px] text-text-secondary">
                  Seat {match.seat}
                </span>
                <span className="text-text-muted text-[10px]">•</span>
                <span className="text-[12px] text-text-muted">
                  {match.time}
                </span>
              </div>
            </div>
          </div>
        ))}

        {matches.length === 0 && (
          <div className="mt-6 text-center">
            <p className="text-[14px] text-text-muted">No matches yet</p>
          </div>
        )}
      </div>

      <TabBar activeTab="matches" />
    </div>
  );
}
