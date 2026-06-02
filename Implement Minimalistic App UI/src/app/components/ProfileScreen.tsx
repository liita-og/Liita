import React from 'react';
import { TabBar } from './TabBar';
import { Avatar } from './Avatar';

export function ProfileScreen() {
  return (
    <div className="w-full h-full pt-[60px] pb-[100px] flex flex-col relative px-[24px] overflow-y-auto">
      <div className="flex flex-col items-center mb-10 shrink-0">
        <Avatar initials="PM" size={88} colorIndex={0} />
        <h1 className="text-[24px] font-medium tracking-tight text-text-primary mt-5 mb-1">Pradyumna</h1>
        <div className="flex items-center gap-2 text-[14px]">
          <span className="text-text-secondary">Seat 20A</span>
          <span className="text-text-muted">•</span>
          <span className="text-text-secondary">Software Engineer</span>
        </div>
      </div>

      <div className="flex justify-between px-6 mb-10 shrink-0">
        <div className="flex flex-col items-center">
          <div className="text-[24px] font-medium text-text-primary mb-1">6</div>
          <div className="text-[12px] text-text-muted">Waves</div>
        </div>
        <div className="w-px bg-border-subtle" />
        <div className="flex flex-col items-center">
          <div className="text-[24px] font-medium text-text-primary mb-1">2</div>
          <div className="text-[12px] text-text-muted">Matches</div>
        </div>
        <div className="w-px bg-border-subtle" />
        <div className="flex flex-col items-center">
          <div className="text-[24px] font-medium text-text-primary mb-1">14</div>
          <div className="text-[12px] text-text-muted">Messages</div>
        </div>
      </div>

      <div className="p-5 rounded-[16px] bg-surface border border-border-subtle mb-4 shrink-0">
        <p className="text-[13px] text-text-secondary mb-3">
          What's something most people don't know about you?
        </p>
        <p className="text-[15px] text-text-primary leading-relaxed font-light">
          I learned to code on a Nokia phone when I was 13
        </p>
      </div>

      <div className="p-5 rounded-[16px] bg-surface border border-border-subtle mb-8 shrink-0 flex items-center justify-between">
        <div>
          <div className="text-[15px] font-medium text-text-primary mb-1">
            EK512
          </div>
          <div className="text-[13px] text-text-muted">
            Dubai → Mumbai
          </div>
        </div>
        <div className="text-right">
          <div className="text-[15px] text-text-primary mb-1">
            Seat 20A
          </div>
          <div className="text-[13px] text-text-muted">
            Economy
          </div>
        </div>
      </div>

      <div className="mt-auto shrink-0 mb-4">
        <button className="w-full py-4 text-text-muted text-[14px] font-medium active:text-text-secondary transition-colors">
          End Flight Session
        </button>
      </div>

      <TabBar activeTab="profile" />
    </div>
  );
}
