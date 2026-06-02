import React from 'react';
import { TabBar } from './TabBar';
import { Wifi, ArrowUp } from 'lucide-react';

export function LoungeScreen() {
  const messages = [
    { id: 1, name: 'Sofia Lin', seat: '22A', text: "Does anyone know if there's wifi on this flight?", time: '10:42 AM', initials: 'SL', color: 2, isMe: false },
    { id: 2, name: 'James Okafor', seat: '7B', text: "There is but it's painfully slow. Download stuff before boarding next time.", time: '10:44 AM', initials: 'JO', color: 1, isMe: false },
    { id: 3, name: 'Priya Mehta', seat: '14C', text: "I've been watching downloaded stuff the whole time, no regrets", time: '10:45 AM', initials: 'PM', color: 0, isMe: false },
    { id: 4, name: 'You', seat: '20A', text: "This app is wild. Didn't know this existed until 5 mins ago", time: '10:48 AM', initials: 'PM', color: 0, isMe: true },
    { id: 5, name: 'Arjun Nair', seat: '31D', text: "Same. Building something similar actually, let's talk", time: '10:50 AM', initials: 'AN', color: 3, isMe: false },
  ];

  return (
    <div className="w-full h-full pt-[50px] pb-[90px] flex flex-col relative">
      <div className="px-[24px] flex items-center justify-between pb-4 border-b border-border-subtle shrink-0">
        <div>
          <h1 className="text-[18px] font-medium tracking-tight text-text-primary">Flight Lounge</h1>
          <p className="text-[13px] text-text-muted mt-0.5">47 passengers · EK512</p>
        </div>
        <Wifi size={18} className="text-text-muted" strokeWidth={1.5} />
      </div>

      <div className="flex-1 overflow-y-auto px-[20px] py-[20px] space-y-5 flex flex-col">
        {messages.map((msg) => (
          <div key={msg.id} className={`flex w-full ${msg.isMe ? 'justify-end' : 'justify-start'}`}>
            <div className={`flex flex-col max-w-[80%] ${msg.isMe ? 'items-end' : 'items-start'}`}>
              {!msg.isMe && (
                <div className="flex items-center gap-2 mb-1 px-1">
                  <span className="text-[12px] font-medium text-text-secondary">{msg.name}</span>
                  <span className="text-[10px] text-text-muted">{msg.seat}</span>
                </div>
              )}
              
              <div className={`p-3 rounded-[16px] text-[14px] leading-relaxed ${
                msg.isMe 
                  ? 'bg-accent text-background rounded-br-[4px]' 
                  : 'bg-surface border border-border-subtle text-text-primary rounded-bl-[4px]'
              }`}>
                {msg.text}
              </div>
              
              <span className="text-[10px] text-text-muted mt-1 px-1">
                {msg.time}
              </span>
            </div>
          </div>
        ))}
      </div>

      <div className="px-[20px] pb-[16px] shrink-0">
        <div className="relative flex items-center bg-surface border border-border-subtle rounded-[16px] p-1.5 focus-within:border-text-secondary transition-colors">
          <input 
            type="text" 
            placeholder="Message the flight..." 
            className="flex-1 bg-transparent border-none text-[14px] text-text-primary placeholder:text-text-muted px-3 outline-none"
            defaultValue="Hello "
          />
          <button className="w-8 h-8 rounded-full bg-accent flex items-center justify-center shrink-0">
            <ArrowUp size={16} className="text-background" strokeWidth={2.5} />
          </button>
        </div>
      </div>

      <TabBar activeTab="lounge" />
    </div>
  );
}
