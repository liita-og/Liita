import 'dart:math';

class TriviaQuestions {
  TriviaQuestions._();

  static const List<Map<String, dynamic>> _all = [
    {
      'q': 'What does BLE stand for?',
      'options': ['Bluetooth Low Energy', 'Byte Layer Encoding', 'Broadcast Link Extension', 'Base Level Encryption'],
      'answer': 0,
    },
    {
      'q': 'What color are aircraft flight data recorders?',
      'options': ['Orange', 'Black', 'Red', 'Yellow'],
      'answer': 0,
    },
    {
      'q': 'What is the typical cruising altitude for a commercial airliner?',
      'options': ['35,000 – 40,000 ft', '10,000 – 15,000 ft', '50,000 – 55,000 ft', '25,000 – 28,000 ft'],
      'answer': 0,
    },
    {
      'q': 'What does "MAYDAY" originate from?',
      'options': ["French 'm'aidez'", 'German Mai Tag', 'Morse code for M', 'NATO phonetic alphabet'],
      'answer': 0,
    },
    {
      'q': 'What is the world\'s busiest airport by passenger traffic?',
      'options': ['Hartsfield-Jackson Atlanta', 'Dubai International', 'London Heathrow', 'Beijing Capital'],
      'answer': 0,
    },
    {
      'q': 'What does ATC stand for in aviation?',
      'options': ['Air Traffic Control', 'Altitude Tracking Center', 'Automated Takeoff Command', 'Aircraft Transponder Code'],
      'answer': 0,
    },
    {
      'q': 'What does VFR stand for?',
      'options': ['Visual Flight Rules', 'Vertical Flight Radius', 'Validated Fuel Ratio', 'Variable Frequency Range'],
      'answer': 0,
    },
    {
      'q': 'What year did the Concorde enter commercial service?',
      'options': ['1976', '1969', '1982', '1971'],
      'answer': 0,
    },
    {
      'q': 'What is the phonetic alphabet word for the letter B?',
      'options': ['Bravo', 'Baker', 'Beta', 'Bourbon'],
      'answer': 0,
    },
    {
      'q': 'In which city is Changi Airport located?',
      'options': ['Singapore', 'Bangkok', 'Hong Kong', 'Kuala Lumpur'],
      'answer': 0,
    },
    {
      'q': 'What does IFR stand for in aviation?',
      'options': ['Instrument Flight Rules', 'International Flight Route', 'In-Flight Refueling', 'Intermediate Frequency Range'],
      'answer': 0,
    },
    {
      'q': 'Which ocean covers the largest area?',
      'options': ['Pacific Ocean', 'Atlantic Ocean', 'Indian Ocean', 'Arctic Ocean'],
      'answer': 0,
    },
    {
      'q': 'How many time zones does Russia span?',
      'options': ['11', '9', '13', '7'],
      'answer': 0,
    },
    {
      'q': 'What does "pax" mean in airline terminology?',
      'options': ['Passengers', 'Packages', 'Parking slots', 'Payment records'],
      'answer': 0,
    },
    {
      'q': 'What is the civil aviation international distress frequency?',
      'options': ['121.5 MHz', '156.8 MHz', '243.0 MHz', '406.0 MHz'],
      'answer': 0,
    },
    {
      'q': 'What does GMT stand for?',
      'options': ['Greenwich Mean Time', 'Global Meridian Time', 'General Map Time', 'Ground Measurement Time'],
      'answer': 0,
    },
    {
      'q': 'The ICAO phonetic alphabet word for S is?',
      'options': ['Sierra', 'Sugar', 'Sam', 'Snake'],
      'answer': 0,
    },
    {
      'q': 'Which company manufactures the 787 Dreamliner?',
      'options': ['Boeing', 'Airbus', 'Bombardier', 'Embraer'],
      'answer': 0,
    },
    {
      'q': 'What does ETA stand for?',
      'options': ['Estimated Time of Arrival', 'Elapsed Time Altitude', 'Engine Thrust Adjustment', 'Expected Terminal Approach'],
      'answer': 0,
    },
    {
      'q': 'What was the first commercial jet airliner to enter service?',
      'options': ['de Havilland Comet', 'Boeing 707', 'Douglas DC-8', 'Sud Aviation Caravelle'],
      'answer': 0,
    },
    {
      'q': 'What does a barometer measure?',
      'options': ['Atmospheric pressure', 'Wind speed', 'Humidity', 'Temperature'],
      'answer': 0,
    },
    {
      'q': 'Which sea lies between Europe and North Africa?',
      'options': ['Mediterranean Sea', 'Red Sea', 'Arabian Sea', 'Caspian Sea'],
      'answer': 0,
    },
    {
      'q': 'What is the currency of Japan?',
      'options': ['Japanese Yen', 'Japanese Won', 'Japanese Baht', 'Japanese Ringgit'],
      'answer': 0,
    },
    {
      'q': 'How many nautical miles equal one degree of latitude?',
      'options': ['60', '69', '100', '45'],
      'answer': 0,
    },
    {
      'q': 'Which country has the most domestic airports?',
      'options': ['United States', 'Russia', 'China', 'Brazil'],
      'answer': 0,
    },
    {
      'q': 'What is the fear of flying formally called?',
      'options': ['Aviophobia', 'Acrophobia', 'Claustrophobia', 'Xenophobia'],
      'answer': 0,
    },
    {
      'q': 'What speed must an aircraft exceed to break the sound barrier?',
      'options': ['~1,235 km/h', '~800 km/h', '~1,600 km/h', '~1,000 km/h'],
      'answer': 0,
    },
    {
      'q': 'Who invented the first successful powered airplane?',
      'options': ['Wright Brothers', 'Otto Lilienthal', 'Samuel Langley', 'Henri Farman'],
      'answer': 0,
    },
    {
      'q': 'What is the standard atmospheric pressure at sea level?',
      'options': ['1013.25 hPa', '1100 hPa', '900 hPa', '1050 hPa'],
      'answer': 0,
    },
    {
      'q': 'What does the Q in QR code stand for?',
      'options': ['Quick Response', 'Queue Readable', 'Quantum Relay', 'Query Record'],
      'answer': 0,
    },
  ];

  /// Returns [count] randomly selected, shuffled questions.
  static List<Map<String, dynamic>> getShuffled(int count) {
    final copy = List<Map<String, dynamic>>.from(_all);
    copy.shuffle(Random());
    return copy.take(count).toList();
  }
}
