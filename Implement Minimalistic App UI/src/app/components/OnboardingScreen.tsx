import React, { useState } from 'react';
import { ChevronLeft } from 'lucide-react';

export function OnboardingScreen() {
  const [seat, setSeat] = useState('20A');
  const [cabin, setCabin] = useState('Economy');

  return (
    <div className="w-full h-full flex flex-col relative bg-background">
      {/* Minimal Progress Bar */}
      <div className="px-[24px] pt-[12px] flex gap-2 w-full shrink-0">
        {[1, 2, 3, 4, 5, 6].map((step) => (
          <div 
            key={step} 
            className={`flex-1 h-[2px] rounded-full transition-colors ${step <= 3 ? 'bg-text-primary' : 'bg-surface-raised'}`}
          />
        ))}
      </div>

      <div className="px-[16px] pt-[16px] shrink-0">
        <button className="w-[40px] h-[40px] flex items-center justify-center rounded-full active:bg-surface-raised transition-colors">
          <ChevronLeft size={24} className="text-text-primary" strokeWidth={1.5} />
        </button>
      </div>

      <div className="flex-1 flex flex-col justify-center px-[24px] pb-[80px]">
        <div className="text-center mb-12">
          <h1 className="text-[32px] font-medium tracking-tight text-text-primary mb-3">
            Where are you sitting?
          </h1>
          <p className="text-[15px] text-text-secondary leading-relaxed font-light">
            We use this to position you relative to nearby passengers
          </p>
        </div>

        <div className="mb-10 relative max-w-[200px] mx-auto w-full">
          <input
            type="text"
            value={seat}
            onChange={(e) => setSeat(e.target.value.toUpperCase())}
            placeholder="20A"
            className="w-full h-[72px] rounded-[16px] bg-surface border border-border-subtle text-center text-[32px] font-medium text-text-primary placeholder:text-text-muted/50 outline-none focus:border-text-secondary transition-colors"
            maxLength={3}
          />
        </div>

        <div className="flex justify-center gap-2 mb-[60px]">
          {['Economy', 'Business', 'First'].map((type) => (
            <button
              key={type}
              onClick={() => setCabin(type)}
              className={`px-5 py-2.5 rounded-full text-[14px] font-medium transition-all ${
                cabin === type
                  ? 'bg-accent text-background'
                  : 'text-text-muted hover:text-text-secondary'
              }`}
            >
              {type}
            </button>
          ))}
        </div>

        <button className="w-full h-[56px] rounded-[16px] bg-accent text-background text-[16px] font-medium active:scale-[0.98] transition-transform mt-auto">
          Continue
        </button>
      </div>
    </div>
  );
}
