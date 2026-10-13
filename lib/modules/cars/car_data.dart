import 'package:flutter/material.dart';

class CarColor {
  final String name;
  final Color color;
  final bool needsBorder;
  const CarColor(this.name, this.color, {this.needsBorder = false});
}

class CarData {
  static const Map<String, List<String>> brandModels = {
    'Acura': ['ADX', 'Integra', 'MDX', 'NSX', 'RDX', 'RSX', 'TLX', 'ZDX'],
    'Alfa Romeo': ['Giulia', 'Stelvio', 'Tonale'],
    'Audi': [
      'A3', 'A4', 'A4 Allroad', 'A5', 'A5 Cabriolet', 'A5 Sportback',
      'A6', 'A6 Allroad', 'A6 Avant e-tron', 'A6 Sportback e-tron',
      'A7', 'A8', 'e-tron GT', 'Q3', 'Q4 e-tron', 'Q4 Sportback e-tron',
      'Q5', 'Q5 Sportback', 'Q6 e-tron', 'Q7', 'Q8', 'Q8 e-tron',
      'Q8 Sportback e-tron', 'R8', 'RS 3', 'RS 5', 'RS 6 Avant', 'RS 7',
      'RS e-tron GT', 'RS Q8', 'S3', 'S5', 'S6', 'S7', 'S8', 'SQ5',
      'SQ7', 'SQ8', 'SQ8 e-tron', 'SQ8 Sportback e-tron', 'TT', 'TT RS', 'TTS',
    ],
    'BMW': [
      '2 Series', '3 Series', '4 Series', '5 Series', '7 Series', '8 Series',
      '840i', 'Alpina B8', 'Alpina XB7', 'i4', 'i5', 'i7', 'iX',
      'M2', 'M240i', 'M3', 'M340i', 'M4', 'M440i', 'M5', 'M550e', 'M760e',
      'M8', 'M850i', 'X1', 'X2', 'X3', 'X3 M', 'X4', 'X5', 'X5 M',
      'X6', 'X6 M', 'X7', 'XM', 'Z4',
    ],
    'Buick': ['Enclave', 'Encore GX', 'Envision', 'Envista'],
    'Cadillac': [
      'CT4', 'CT5', 'Escalade', 'Escalade IQ', 'Lyriq',
      'Optiq', 'Vistiq', 'XT4', 'XT5', 'XT6',
    ],
    'Chevrolet': [
      'Blazer', 'Blazer EV', 'Colorado', 'Corvette', 'Equinox', 'Equinox EV',
      'Silverado 1500', 'Silverado EV', 'Suburban', 'Tahoe', 'Trailblazer',
      'Traverse', 'Trax',
    ],
    'Chrysler': ['Pacifica', 'Pacifica Hybrid', 'Voyager'],
    'Dodge': ['Charger Daytona', 'Durango', 'Hornet', 'Hornet Plug-In Hybrid'],
    'Fiat': ['500e'],
    'Ford': [
      'Bronco', 'Bronco Sport', 'Escape', 'Escape Hybrid', 'Escape Plug-In Hybrid',
      'Expedition', 'Explorer', 'F-150', 'F-150 Lightning', 'Maverick',
      'Mustang', 'Mustang Mach-E', 'Ranger',
    ],
    'Genesis': [
      'Electrified G80', 'Electrified GV70', 'G70', 'G80', 'G90',
      'GV60', 'GV70', 'GV80',
    ],
    'GMC': [
      'Acadia', 'Canyon', 'Hummer EV Pickup', 'Hummer EV SUV',
      'Sierra 1500', 'Sierra EV', 'Terrain', 'Yukon',
    ],
    'Honda': [
      'Accord', 'Accord Hybrid', 'Civic', 'Civic Hatchback', 'Civic Hybrid',
      'Civic Hybrid Hatchback', 'Civic Type R', 'Clarity', 'CR-V', 'CR-V e:FCEV',
      'CR-V Hybrid', 'CR-Z', 'Crosstour', 'Element', 'Fit', 'HR-V',
      'HR-V Sport EV', 'Insight', 'Odyssey', 'Passport', 'Passport TrailSport',
      'Pilot', 'Prelude', 'Prologue', 'Ridgeline', 'S2000',
    ],
    'Hyundai': [
      'Accent', 'Azera', 'Elantra', 'Elantra Hybrid', 'Elantra N', 'Entourage',
      'Genesis Coupe', 'Ioniq', 'Ioniq 5', 'Ioniq 6', 'Ioniq 9', 'Ioniq Hybrid',
      'Ioniq Plug-In Hybrid', 'Kona', 'Kona Electric', 'Nexo', 'Palisade',
      'Palisade Hybrid', 'Santa Cruz', 'Santa Fe', 'Santa Fe Hybrid', 'Sonata',
      'Sonata Hybrid', 'Tiburon', 'Tucson', 'Tucson Hybrid', 'Tucson Plug-In Hybrid',
      'Veloster', 'Veloster N', 'Venue', 'Venue N', 'Veracruz', 'XG350',
    ],
    'Ineos': ['Fusilier', 'Grenadier Quartermaster', 'Grenadier Station Wagon'],
    'Infiniti': [
      'EX35', 'FX35', 'G35', 'G37', 'Q45', 'Q50', 'Q60', 'Q70',
      'QX30', 'QX50', 'QX55', 'QX56', 'QX60', 'QX70', 'QX80',
    ],
    'Jaguar': [
      'E-Pace', 'F-Pace', 'F-Type', 'I-Pace', 'S-Type', 'X-Type',
      'XE', 'XF', 'XJ', 'XJS', 'XK',
    ],
    'Jeep': [
      'Cherokee', 'CJ', 'Comanche', 'Commander', 'Commander L', 'Compass',
      'Gladiator', 'Grand Cherokee', 'Grand Cherokee 4xe', 'Grand Cherokee L',
      'Grand Wagoneer', 'Liberty', 'Patriot', 'Recon', 'Renegade',
      'Wagoneer', 'Wrangler', 'Wrangler 4xe',
    ],
    'Kia': [
      'Amanti', 'Borrego', 'Cadenza', 'Carnival', 'Carnival Hybrid', 'EV3',
      'EV4', 'EV5', 'EV6', 'EV9', 'Forte', 'K4', 'K5', 'Niro', 'Niro EV',
      'Niro Plug-In Hybrid', 'Optima', 'Rio', 'Rondo', 'Sedona', 'Seltos',
      'Sephia', 'Sorento', 'Sorento Hybrid', 'Sorento Plug-In Hybrid', 'Soul',
      'Sportage', 'Sportage Hybrid', 'Sportage Plug-In Hybrid', 'Stinger', 'Telluride',
    ],
    'Land Rover': [
      'Defender', 'Discovery', 'Discovery Sport', 'Freelander', 'LR2', 'LR3', 'LR4',
      'Range Rover', 'Range Rover Classic', 'Range Rover Electric', 'Range Rover Evoque',
      'Range Rover Sport', 'Range Rover SV', 'Range Rover Velar',
    ],
    'Lexus': [
      'CT', 'ES', 'ES Electric', 'ES Hybrid', 'GS', 'GX', 'HS', 'IS', 'LC',
      'LFA', 'LS', 'LX', 'NX', 'NX 450h+', 'NX Hybrid', 'NX Plug-In Hybrid',
      'RC', 'RX', 'RX Hybrid', 'RX L', 'RX Plug-In Hybrid', 'RZ', 'RZ 550e',
      'SC', 'TX', 'TX Hybrid', 'TX Plug-In Hybrid', 'UX', 'UX Hybrid',
    ],
    'Lincoln': [
      'Aviator', 'Blackwood', 'Continental', 'Corsair', 'Mark LT', 'MKC',
      'MKS', 'MKT', 'MKZ', 'Nautilus', 'Navigator', 'Star', 'Town Car',
    ],
    'Lucid': ['Air', 'Gravity', 'Sapphire'],
    'Maserati': ['GranTurismo', 'Grecale', 'Grecale Folgore', 'Levante', 'Quattroporte'],
    'Mazda': [
      'CX-30', 'CX-5', 'CX-50', 'CX-50 Hybrid', 'CX-70', 'CX-70 PHEV',
      'CX-90', 'CX-90 PHEV', 'Mazda3', 'MX-5 Miata',
    ],
    'Mercedes-Benz': [
      'C-Class', 'CLA Class', 'CLE Class', 'E-Class', 'EQB', 'EQE Sedan',
      'EQE SUV', 'EQS Sedan', 'EQS SUV', 'G 63', 'G-Class', 'G-Class EV',
      'GLA Class', 'GLB Class', 'GLC Class', 'GLC Plug-In Hybrid', 'GLE 53',
      'GLE Class', 'GLE Plug-In Hybrid', 'GLS Class', 'GT', 'S-Class', 'SL Class',
    ],
    'Mini': ['Cooper', 'Countryman', 'Countryman EV', 'Electric Hardtop'],
    'Mitsubishi': [
      'Eclipse Cross', 'Outlander', 'Outlander Plug-In Hybrid', 'Outlander Sport',
    ],
    'Nissan': [
      'Altima', 'Ariya', 'Armada', 'Frontier', 'GT-R', 'Kicks', 'Leaf',
      'Murano', 'Pathfinder', 'Rogue', 'Sentra', 'Versa', 'Z',
    ],
    'Polestar': ['2', '3', '4'],
    'Porsche': [
      '911', 'Boxster', 'Cayenne', 'Cayenne Hybrid', 'Cayman',
      'Macan', 'Macan EV', 'Panamera', 'Taycan',
    ],
    'Ram': ['1500'],
    'Rivian': ['R1S', 'R1T'],
    'Subaru': [
      'Ascent', 'BRZ', 'Crosstrek', 'Crosstrek Hybrid', 'Forester',
      'Forester Hybrid', 'Impreza', 'Legacy', 'Outback', 'Solterra',
      'Trailseeker', 'WRX',
    ],
    'Tesla': ['Cybercab', 'Cybertruck', 'Model 3', 'Model S', 'Model X', 'Model Y', 'Semi'],
    'Toyota': [
      '4Runner', 'Avalon', 'bZ', 'bZ Woodland', 'C-HR', 'Camry', 'Camry Hybrid',
      'Corolla', 'Corolla Cross', 'Corolla Cross Hybrid', 'Corolla Hatchback',
      'Corolla Hybrid', 'Crown', 'Crown Signia', 'GR Corolla', 'GR86',
      'Grand Highlander', 'Grand Highlander Hybrid', 'Highlander', 'Highlander Hybrid',
      'Land Cruiser', 'Mirai', 'Prius', 'Prius Plug-In Hybrid', 'RAV4',
      'RAV4 Hybrid', 'RAV4 Plug-In Hybrid', 'Sequoia', 'Sienna', 'Supra',
      'Tacoma', 'Tundra', 'Venza',
    ],
    'Volkswagen': [
      'Arteon', 'Atlas', 'Atlas Cross Sport', 'Golf R', 'GTI', 'ID. Buzz',
      'ID.4', 'ID.7', 'Jetta', 'Jetta GLI', 'Passat', 'Taos', 'Tiguan',
    ],
    'Volvo': [
      'EC40', 'ES90', 'EX30', 'EX30 Cross Country', 'EX40', 'EX60', 'EX90',
      'S60', 'S60 Plug-In Hybrid', 'S90', 'S90 Plug-In Hybrid', 'V60',
      'V60 Cross Country', 'V90', 'V90 Cross Country', 'XC40', 'XC60',
      'XC60 Plug-in Hybrid', 'XC90', 'XC90 Plug-In Hybrid',
    ],
  };

  static const List<String> featuredBrands = [
    'Toyota', 'Ford', 'Honda', 'Chevrolet',
    'BMW', 'Mercedes-Benz', 'Tesla', 'Jeep',
  ];

  static List<String> get allBrands {
    final brands = brandModels.keys.toList();
    brands.sort();
    return brands;
  }

  static Map<String, List<String>> get brandsByLetter {
    final result = <String, List<String>>{};
    for (final brand in allBrands) {
      final first = brand[0].toUpperCase();
      final key = RegExp(r'[A-Z]').hasMatch(first) ? first : '#';
      result.putIfAbsent(key, () => []).add(brand);
    }
    return result;
  }

  static List<String> get availableLetters {
    final letters = brandsByLetter.keys.toList()..sort();
    if (letters.contains('#')) {
      letters.remove('#');
      letters.insert(0, '#');
    }
    return letters;
  }

  static const List<String> bodyTypes = [
    'Sedan', 'SUV', 'Pickup Truck', 'Hatchback', 'Coupe',
    'Convertible', 'Wagon', 'Minivan', 'Van', 'Sports Car', 'Crossover',
  ];

  static const List<String> fuelTypes = [
    'Gasoline', 'Diesel', 'Hybrid', 'Plug-in Hybrid',
    'Electric', 'Flex Fuel', 'Hydrogen',
  ];

  static const List<String> transmissions = [
    'Automatic', 'Manual', 'CVT', 'Semi-Auto / DCT',
  ];

  static const List<String> driveTypes = [
    'FWD', 'RWD', 'AWD', '4WD / 4x4',
  ];

  static const List<String> engineSizes = [
    'Under 1.5L', '1.5L – 2.0L', '2.0L – 2.5L',
    '2.5L – 3.0L', '3.0L – 4.0L', '4.0L+', 'Electric Motor',
  ];

  static const List<String> steeringTypes = [
    'Hydraulic', 'Electric (EPS)', 'Electro-Hydraulic',
  ];

  static const List<String> optionalFeatures = [
    'Air Conditioning', 'Heated Seats', 'Sunroof / Moonroof',
    'Navigation (GPS)', 'Bluetooth', 'Backup Camera',
    'Cruise Control', 'Adaptive Cruise', 'Lane Assist',
    'Apple CarPlay / Android Auto', 'Premium Sound System',
    'Keyless Entry', 'Remote Start', 'Parking Sensors',
    'Blind Spot Monitor', 'Leather Seats', 'Third Row Seating',
    'Ventilated Seats', 'Heads-Up Display',
  ];

  static const List<String> conditionItems = [
    'Single Owner', 'Full Service History', "Owner's Manual",
    'Spare Key', 'Active Manufacturer Warranty', 'Certified Pre-Owned (CPO)',
    'Accident Free', 'Up-to-Date Registration',
  ];

  static const List<String> sortOptions = [
    'Most Relevant', 'Newest Listing', 'Lowest Price',
    'Highest Price', 'Lowest Mileage', 'Newest Year', 'Oldest Year',
  ];

  // Maps brand display name → logo filename (without extension) in assets/car_logos/
  static const Map<String, String> brandLogoFiles = {
    'Acura': 'acura',
    'Alfa Romeo': 'alfa-romeo',
    'Audi': 'audi',
    'BMW': 'bmw',
    'Buick': 'buick',
    'Cadillac': 'cadillac',
    'Chevrolet': 'chevrolet',
    'Chrysler': 'chrysler',
    'Dodge': 'dodge',
    'Fiat': 'fiat',
    'Ford': 'ford',
    'Genesis': 'genesis',
    'GMC': 'gmc',
    'Honda': 'honda',
    'Hyundai': 'hyundai',
    'Infiniti': 'infiniti',
    'Jaguar': 'jaguar',
    'Jeep': 'jeep',
    'Kia': 'kia',
    'Land Rover': 'land-rover',
    'Lexus': 'lexus',
    'Lincoln': 'lincoln',
    'Lucid': 'lucid',
    'Maserati': 'maserati',
    'Mazda': 'mazda',
    'Mercedes-Benz': 'mercedes-benz',
    'Mini': 'mini',
    'Mitsubishi': 'mitsubishi',
    'Nissan': 'nissan',
    'Polestar': 'polestar',
    'Porsche': 'porsche',
    'Ram': 'ram',
    'Rivian': 'rivian',
    'Subaru': 'subaru',
    'Tesla': 'tesla',
    'Toyota': 'toyota',
    'Volkswagen': 'volkswagen',
    'Volvo': 'volvo',
  };

  static String? logoAssetPath(String brand) {
    final file = brandLogoFiles[brand];
    return file != null ? 'assets/car_logos/$file.png' : null;
  }

  static final List<CarColor> colorOptions = [
    const CarColor('Black', Color(0xFF1A1A1A)),
    const CarColor('White', Color(0xFFF8F8F8), needsBorder: true),
    const CarColor('Silver', Color(0xFFC0C0C0)),
    const CarColor('Gray', Color(0xFF707070)),
    const CarColor('Red', Color(0xFFBB1122)),
    const CarColor('Blue', Color(0xFF1A4F9E)),
    const CarColor('Navy', Color(0xFF0A1F5C)),
    const CarColor('Green', Color(0xFF1B5E20)),
    const CarColor('Brown', Color(0xFF5D4037)),
    const CarColor('Beige', Color(0xFFE8DCBC)),
    const CarColor('Gold', Color(0xFFD4AF37)),
    const CarColor('Orange', Color(0xFFCC4400)),
    const CarColor('Yellow', Color(0xFFE6B800)),
    const CarColor('Purple', Color(0xFF5E1589)),
    const CarColor('Maroon', Color(0xFF7B0000)),
  ];
}
