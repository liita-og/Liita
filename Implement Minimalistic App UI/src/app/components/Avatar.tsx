import React from 'react';

// Premium, muted, monochrome-adjacent palette
const COLORS = ['#27272A', '#1C1C1F', '#3F3F46', '#18181B'];

export function Avatar({ 
  initials, 
  size = 64, 
  colorIndex = 0 
}: { 
  initials: string; 
  size?: number; 
  colorIndex?: number;
}) {
  const bgColor = COLORS[colorIndex % COLORS.length];
  const fontSize = Math.max(10, Math.floor(size * 0.35));
  
  return (
    <div 
      className="rounded-full flex items-center justify-center text-[#FAFAFA] font-medium shrink-0 border border-[rgba(255,255,255,0.04)]"
      style={{
        width: size,
        height: size,
        backgroundColor: bgColor,
        fontSize,
      }}
    >
      {initials}
    </div>
  );
}
