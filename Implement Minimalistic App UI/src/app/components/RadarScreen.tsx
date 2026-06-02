import React from 'react';
import { TabBar } from './TabBar';
import { Avatar } from './Avatar';

export function RadarScreen() {
  const cards = [
    { initials: 'PM', name: 'Priya Mehta', seat: '14C', job: 'UX Designer', answer: "I'll talk to anyone if they bring good energy", color: 0 },
    { initials: 'JO', name: 'James Okafor', seat: '7B', job: 'Photographer', answer: "I once hitchhiked across three countries", color: 1 },
    { initials: 'SL', name: 'Sofia Lin', seat: '22A', job: 'Architect', answer: "Coffee and deadlines, that's the whole personality", color: 2 },
    { initials: 'AN', name: 'Arjun Nair', seat: '31D', job: 'Startup Founder', answer: "Failed twice. Third time's the flight.", color: 3 },
  ];

  return (
    <div className="w-full h-full pt-[60px] pb-[100px] flex flex-col relative">
      <div className="px-[24px] flex items-center justify-between mb-8 shrink-0">
        <h1 className="text-[24px] font-medium tracking-tight text-text-primary">Radar</h1>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-surface border border-border-subtle">
          <div className="w-1.5 h-1.5 rounded-full bg-accent animate-pulse" />
          <span className="text-[12px] font-medium text-text-primary">14 nearby</span>
        </div>
      </div>

      <div className="flex-1 relative flex items-center justify-center px-[24px]">
        {/* Card Stack */}
        <div className="relative w-full h-[460px] flex items-center justify-center">
          {/* Reversed so index 0 is on top */}
          {[...cards].reverse().map((card, i) => {
            const index = cards.length - 1 - i;
            const isFront = index === 0;
            const scale = 1 - (index * 0.05);
            const translateY = index * 32; // Peeking below
            const opacity = 1 - (index * 0.15);
            const zIndex = 10 - index;
            
            return (
              <div
                key={index}
                className={`absolute w-full rounded-[20px] border border-border-subtle bg-surface overflow-hidden transition-all duration-300 ${isFront ? 'shadow-[0_16px_40px_rgba(0,0,0,0.5)]' : ''}`}
                style={{
                  height: 400,
                  transform: `translateY(${translateY}px) scale(${scale})`,
                  opacity,
                  zIndex,
                  transformOrigin: 'top center'
                }}
              >
                {isFront ? (
                  <div className="p-6 flex flex-col h-full">
                    <div className="flex items-center gap-4">
                      <Avatar initials={card.initials} size={56} colorIndex={card.color} />
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <h2 className="text-[18px] font-medium truncate tracking-tight text-text-primary">{card.name}</h2>
                          <span className="text-[13px] text-text-muted">·</span>
                          <span className="text-[13px] text-text-secondary">
                            {card.seat}
                          </span>
                        </div>
                        <p className="text-[14px] text-text-muted">{card.job}</p>
                      </div>
                    </div>
                    
                    <div className="flex-1 mt-8">
                      <p className="text-[16px] text-text-primary leading-relaxed font-light">
                        "{card.answer}"
                      </p>
                    </div>
                    
                    <div className="flex gap-3 mt-auto">
                      <button className="flex-1 bg-accent text-background text-[14px] font-medium py-3 rounded-[12px] active:scale-[0.98] transition-transform">
                        Wave
                      </button>
                    </div>
                  </div>
                ) : index === 1 ? (
                  <div className="p-6 flex items-center gap-4 opacity-40 blur-[1px]">
                    <div className="w-14 h-14 rounded-full bg-surface-raised" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 w-32 bg-surface-raised rounded" />
                      <div className="h-3 w-20 bg-surface-raised rounded" />
                    </div>
                  </div>
                ) : (
                  <div className="w-full h-full bg-surface" />
                )}
              </div>
            );
          })}
        </div>
      </div>

      <div className="flex justify-center items-center gap-2 mb-6">
        <div className="w-4 h-1 rounded-full bg-accent" />
        <div className="w-1 h-1 rounded-full bg-surface-raised" />
        <div className="w-1 h-1 rounded-full bg-surface-raised" />
        <div className="w-1 h-1 rounded-full bg-surface-raised" />
      </div>

      <TabBar activeTab="radar" />
    </div>
  );
}
