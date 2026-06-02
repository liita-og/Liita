import React from 'react';
import { Radar, MessageSquare, Gamepad2, Users, User } from 'lucide-react';

export function TabBar({ activeTab }: { activeTab: 'radar' | 'lounge' | 'games' | 'matches' | 'profile' }) {
  const tabs = [
    { id: 'radar', icon: Radar },
    { id: 'lounge', icon: MessageSquare },
    { id: 'games', icon: Gamepad2 },
    { id: 'matches', icon: Users },
    { id: 'profile', icon: User }
  ] as const;

  return (
    <div className="absolute bottom-[24px] left-1/2 -translate-x-1/2 z-40">
      <div className="flex items-center justify-between px-6 py-3.5 rounded-full bg-[rgba(18,18,20,0.85)] backdrop-blur-xl border border-border-subtle shadow-[0_8px_32px_rgba(0,0,0,0.5)] gap-6">
        {tabs.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeTab === tab.id;
          return (
            <div key={tab.id} className="relative flex flex-col items-center justify-center cursor-pointer group">
              <Icon 
                size={22} 
                className={`transition-colors ${isActive ? 'text-text-primary' : 'text-text-muted group-hover:text-text-secondary'}`} 
                strokeWidth={isActive ? 2 : 1.5}
              />
              {isActive && (
                <div className="absolute -bottom-2.5 w-1 h-1 rounded-full bg-text-primary" />
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}
