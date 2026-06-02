import React from 'react';
import { RadarScreen } from './components/RadarScreen';
import { LoungeScreen } from './components/LoungeScreen';
import { GamesScreen } from './components/GamesScreen';
import { MatchesScreen } from './components/MatchesScreen';
import { ProfileScreen } from './components/ProfileScreen';
import { OnboardingScreen } from './components/OnboardingScreen';

export default function App() {
  return (
    <div className="min-h-screen p-8 flex flex-wrap gap-12 justify-center items-center bg-[#000000]">
      <ScreenWrapper>
        <RadarScreen />
      </ScreenWrapper>

      
      <ScreenWrapper>
        <LoungeScreen />
      </ScreenWrapper>
      
      <ScreenWrapper>
        <GamesScreen />
      </ScreenWrapper>
      
      <ScreenWrapper>
        <MatchesScreen />
      </ScreenWrapper>
      
      <ScreenWrapper>
        <ProfileScreen />
      </ScreenWrapper>
      
      <ScreenWrapper>
        <OnboardingScreen />
      </ScreenWrapper>
    </div>
  );
}

function ScreenWrapper({ children }: { children: React.ReactNode }) {
  return (
    <div 
      className="relative flex flex-col bg-background overflow-hidden shadow-2xl shrink-0"
      style={{ 
        width: 390, 
        height: 844, 
        borderRadius: 40,
        boxShadow: '0 24px 80px rgba(0,0,0,0.5), inset 0 0 0 1px rgba(255,255,255,0.1)'
      }}
    >
      {/* Notch simulation for realism */}
      <div className="absolute top-0 left-1/2 -translate-x-1/2 w-[120px] h-[30px] bg-black rounded-b-[20px] z-50"></div>
      
      {/* Content */}
      <div className="flex-1 w-full h-full relative overflow-y-auto overflow-x-hidden">
        {children}
      </div>
    </div>
  );
}
