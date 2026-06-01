class SurahInfo {
  final int number;
  final String nameArabic;
  final String nameTranslit;
  final String nameEnglish;
  final int ayahCount;

  const SurahInfo(this.number, this.nameArabic, this.nameTranslit,
      this.nameEnglish, this.ayahCount);

  @override
  String toString() => '$number. $nameTranslit ($nameArabic)';
}

const List<SurahInfo> kSurahs = [
  SurahInfo(1,   'الفاتحة',       'Al-Fatiha',       'The Opening',         7),
  SurahInfo(2,   'البقرة',        'Al-Baqarah',      'The Cow',             286),
  SurahInfo(3,   'آل عمران',      'Ali \'Imran',      'Family of Imran',     200),
  SurahInfo(4,   'النساء',        'An-Nisa',         'The Women',           176),
  SurahInfo(5,   'المائدة',       'Al-Ma\'idah',      'The Table Spread',    120),
  SurahInfo(6,   'الأنعام',       'Al-An\'am',        'The Cattle',          165),
  SurahInfo(7,   'الأعراف',       'Al-A\'raf',        'The Heights',         206),
  SurahInfo(8,   'الأنفال',       'Al-Anfal',        'The Spoils of War',   75),
  SurahInfo(9,   'التوبة',        'At-Tawbah',       'The Repentance',      129),
  SurahInfo(10,  'يونس',          'Yunus',            'Jonah',               109),
  SurahInfo(11,  'هود',           'Hud',              'Hud',                 123),
  SurahInfo(12,  'يوسف',          'Yusuf',            'Joseph',              111),
  SurahInfo(13,  'الرعد',         'Ar-Ra\'d',         'The Thunder',         43),
  SurahInfo(14,  'إبراهيم',       'Ibrahim',          'Abraham',             52),
  SurahInfo(15,  'الحجر',         'Al-Hijr',          'The Rocky Tract',     99),
  SurahInfo(16,  'النحل',         'An-Nahl',          'The Bee',             128),
  SurahInfo(17,  'الإسراء',       'Al-Isra',          'The Night Journey',   111),
  SurahInfo(18,  'الكهف',         'Al-Kahf',          'The Cave',            110),
  SurahInfo(19,  'مريم',          'Maryam',           'Mary',                98),
  SurahInfo(20,  'طه',            'Ta-Ha',            'Ta-Ha',               135),
  SurahInfo(21,  'الأنبياء',      'Al-Anbya',         'The Prophets',        112),
  SurahInfo(22,  'الحج',          'Al-Hajj',          'The Pilgrimage',      78),
  SurahInfo(23,  'المؤمنون',      'Al-Mu\'minun',     'The Believers',       118),
  SurahInfo(24,  'النور',         'An-Nur',           'The Light',           64),
  SurahInfo(25,  'الفرقان',       'Al-Furqan',        'The Criterion',       77),
  SurahInfo(26,  'الشعراء',       'Ash-Shu\'ara',     'The Poets',           227),
  SurahInfo(27,  'النمل',         'An-Naml',          'The Ant',             93),
  SurahInfo(28,  'القصص',         'Al-Qasas',         'The Stories',         88),
  SurahInfo(29,  'العنكبوت',      'Al-\'Ankabut',     'The Spider',          69),
  SurahInfo(30,  'الروم',         'Ar-Rum',           'The Romans',          60),
  SurahInfo(31,  'لقمان',         'Luqman',           'Luqman',              34),
  SurahInfo(32,  'السجدة',        'As-Sajdah',        'The Prostration',     30),
  SurahInfo(33,  'الأحزاب',       'Al-Ahzab',         'The Combined Forces', 73),
  SurahInfo(34,  'سبأ',           'Saba',             'Sheba',               54),
  SurahInfo(35,  'فاطر',          'Fatir',            'Originator',          45),
  SurahInfo(36,  'يس',            'Ya-Sin',           'Ya Sin',              83),
  SurahInfo(37,  'الصافات',       'As-Saffat',        'Those Who Set the Ranks', 182),
  SurahInfo(38,  'ص',             'Sad',              'Sad',                 88),
  SurahInfo(39,  'الزمر',         'Az-Zumar',         'The Troops',          75),
  SurahInfo(40,  'غافر',          'Ghafir',           'The Forgiver',        85),
  SurahInfo(41,  'فصلت',          'Fussilat',         'Explained in Detail', 54),
  SurahInfo(42,  'الشورى',        'Ash-Shura',        'The Consultation',    53),
  SurahInfo(43,  'الزخرف',        'Az-Zukhruf',       'The Ornaments of Gold', 89),
  SurahInfo(44,  'الدخان',        'Ad-Dukhan',        'The Smoke',           59),
  SurahInfo(45,  'الجاثية',       'Al-Jathiyah',      'The Crouching',       37),
  SurahInfo(46,  'الأحقاف',       'Al-Ahqaf',         'The Wind-curved Sandhills', 35),
  SurahInfo(47,  'محمد',          'Muhammad',         'Muhammad',            38),
  SurahInfo(48,  'الفتح',         'Al-Fath',          'The Victory',         29),
  SurahInfo(49,  'الحجرات',       'Al-Hujurat',       'The Rooms',           18),
  SurahInfo(50,  'ق',             'Qaf',              'Qaf',                 45),
  SurahInfo(51,  'الذاريات',      'Adh-Dhariyat',     'The Winnowing Winds', 60),
  SurahInfo(52,  'الطور',         'At-Tur',           'The Mount',           49),
  SurahInfo(53,  'النجم',         'An-Najm',          'The Star',            62),
  SurahInfo(54,  'القمر',         'Al-Qamar',         'The Moon',            55),
  SurahInfo(55,  'الرحمن',        'Ar-Rahman',        'The Beneficent',      78),
  SurahInfo(56,  'الواقعة',       'Al-Waqi\'ah',      'The Inevitable',      96),
  SurahInfo(57,  'الحديد',        'Al-Hadid',         'The Iron',            29),
  SurahInfo(58,  'المجادلة',      'Al-Mujadila',      'The Pleading Woman',  22),
  SurahInfo(59,  'الحشر',         'Al-Hashr',         'The Exile',           24),
  SurahInfo(60,  'الممتحنة',      'Al-Mumtahanah',    'She That is to be Examined', 13),
  SurahInfo(61,  'الصف',          'As-Saf',           'The Ranks',           14),
  SurahInfo(62,  'الجمعة',        'Al-Jumu\'ah',      'The Congregation',    11),
  SurahInfo(63,  'المنافقون',     'Al-Munafiqun',     'The Hypocrites',      11),
  SurahInfo(64,  'التغابن',       'At-Taghabun',      'Mutual Disillusion',  18),
  SurahInfo(65,  'الطلاق',        'At-Talaq',         'The Divorce',         12),
  SurahInfo(66,  'التحريم',       'At-Tahrim',        'The Prohibition',     12),
  SurahInfo(67,  'الملك',         'Al-Mulk',          'The Sovereignty',     30),
  SurahInfo(68,  'القلم',         'Al-Qalam',         'The Pen',             52),
  SurahInfo(69,  'الحاقة',        'Al-Haqqah',        'The Reality',         52),
  SurahInfo(70,  'المعارج',       'Al-Ma\'arij',      'The Ascending Stairways', 44),
  SurahInfo(71,  'نوح',           'Nuh',              'Noah',                28),
  SurahInfo(72,  'الجن',          'Al-Jinn',          'The Jinn',            28),
  SurahInfo(73,  'المزمل',        'Al-Muzzammil',     'The Enshrouded One',  20),
  SurahInfo(74,  'المدثر',        'Al-Muddaththir',   'The Cloaked One',     56),
  SurahInfo(75,  'القيامة',       'Al-Qiyamah',       'The Resurrection',    40),
  SurahInfo(76,  'الإنسان',       'Al-Insan',         'The Man',             31),
  SurahInfo(77,  'المرسلات',      'Al-Mursalat',      'The Emissaries',      50),
  SurahInfo(78,  'النبأ',         'An-Naba',          'The Tidings',         40),
  SurahInfo(79,  'النازعات',      'An-Nazi\'at',      'Those Who Drag Forth', 46),
  SurahInfo(80,  'عبس',           '\'Abasa',          'He Frowned',          42),
  SurahInfo(81,  'التكوير',       'At-Takwir',        'The Overthrowing',    29),
  SurahInfo(82,  'الانفطار',      'Al-Infitar',       'The Cleaving',        19),
  SurahInfo(83,  'المطففين',      'Al-Mutaffifin',    'The Defrauding',      36),
  SurahInfo(84,  'الانشقاق',      'Al-Inshiqaq',      'The Sundering',       25),
  SurahInfo(85,  'البروج',        'Al-Buruj',         'The Mansions of the Stars', 22),
  SurahInfo(86,  'الطارق',        'At-Tariq',         'The Morning Star',    17),
  SurahInfo(87,  'الأعلى',        'Al-A\'la',         'The Most High',       19),
  SurahInfo(88,  'الغاشية',       'Al-Ghashiyah',     'The Overwhelming',    26),
  SurahInfo(89,  'الفجر',         'Al-Fajr',          'The Dawn',            30),
  SurahInfo(90,  'البلد',         'Al-Balad',         'The City',            20),
  SurahInfo(91,  'الشمس',         'Ash-Shams',        'The Sun',             15),
  SurahInfo(92,  'الليل',         'Al-Layl',          'The Night',           21),
  SurahInfo(93,  'الضحى',         'Ad-Duha',          'The Morning Hours',   11),
  SurahInfo(94,  'الشرح',         'Ash-Sharh',        'The Relief',          8),
  SurahInfo(95,  'التين',         'At-Tin',           'The Fig',             8),
  SurahInfo(96,  'العلق',         'Al-\'Alaq',        'The Clot',            19),
  SurahInfo(97,  'القدر',         'Al-Qadr',          'The Power',           5),
  SurahInfo(98,  'البينة',        'Al-Bayyinah',      'The Clear Proof',     8),
  SurahInfo(99,  'الزلزلة',       'Az-Zalzalah',      'The Earthquake',      8),
  SurahInfo(100, 'العاديات',      'Al-\'Adiyat',      'The Courser',         11),
  SurahInfo(101, 'القارعة',       'Al-Qari\'ah',      'The Calamity',        11),
  SurahInfo(102, 'التكاثر',       'At-Takathur',      'The Rivalry in World Increase', 8),
  SurahInfo(103, 'العصر',         'Al-\'Asr',         'The Declining Day',   3),
  SurahInfo(104, 'الهمزة',        'Al-Humazah',       'The Traducer',        9),
  SurahInfo(105, 'الفيل',         'Al-Fil',           'The Elephant',        5),
  SurahInfo(106, 'قريش',          'Quraysh',          'Quraysh',             4),
  SurahInfo(107, 'الماعون',       'Al-Ma\'un',        'The Small Kindnesses', 7),
  SurahInfo(108, 'الكوثر',        'Al-Kawthar',       'The Abundance',       3),
  SurahInfo(109, 'الكافرون',      'Al-Kafirun',       'The Disbelievers',    6),
  SurahInfo(110, 'النصر',         'An-Nasr',          'The Divine Support',  3),
  SurahInfo(111, 'المسد',         'Al-Masad',         'The Palm Fibre',      5),
  SurahInfo(112, 'الإخلاص',       'Al-Ikhlas',        'The Sincerity',       4),
  SurahInfo(113, 'الفلق',         'Al-Falaq',         'The Daybreak',        5),
  SurahInfo(114, 'الناس',         'An-Nas',           'Mankind',             6),
];

/// Returns the 1-based global ayah index across the whole Quran (1–6236).
int globalAyahNumber(int surah, int ayah) {
  int cumulative = 0;
  for (int i = 0; i < surah - 1; i++) {
    cumulative += kSurahs[i].ayahCount;
  }
  return cumulative + ayah;
}

/// Minshawi Murattal — cdn.islamic.network, 128 kbps, addressed by global ayah number.
String minshawuiUrl(int surah, int ayah) {
  final global = globalAyahNumber(surah, ayah);
  return 'https://cdn.islamic.network/quran/audio/128/ar.minshawi/$global.mp3';
}

/// Bismillah for a given surah (global ayah 1 = Surah 1 Ayah 1 = Bismillah in Minshawi's voice).
/// Returns null for Surah 1 (Bismillah IS ayah 1) and Surah 9 (no Bismillah).
String? minshawiBismillahUrl(int surah) {
  if (surah == 1 || surah == 9) return null;
  // Global ayah 1 is always "Bismillahi r-rahmani r-rahim" — same for all surahs
  return 'https://cdn.islamic.network/quran/audio/128/ar.minshawi/1.mp3';
}
