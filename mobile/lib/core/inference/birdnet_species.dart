class BirdnetSpecies {
  const BirdnetSpecies({
    required this.outputIndex,
    required this.scientificName,
    required this.nameZh,
    required this.nameEn,
  });

  final int outputIndex;
  final String scientificName;
  final String nameZh;
  final String nameEn;
}

const hangzhouBirdnetSpecies = <BirdnetSpecies>[
  BirdnetSpecies(
    outputIndex: 1550,
    scientificName: 'Copsychus saularis',
    nameZh: '鹊鸲',
    nameEn: 'Oriental Magpie-Robin',
  ),
  BirdnetSpecies(
    outputIndex: 2420,
    scientificName: 'Gallinula chloropus',
    nameZh: '黑水鸡',
    nameEn: 'Eurasian Moorhen',
  ),
  BirdnetSpecies(
    outputIndex: 5149,
    scientificName: 'Pycnonotus sinensis',
    nameZh: '白头鹎',
    nameEn: 'Light-vented Bulbul',
  ),
  BirdnetSpecies(
    outputIndex: 5746,
    scientificName: 'Streptopelia chinensis',
    nameZh: '珠颈斑鸠',
    nameEn: 'Spotted Dove',
  ),
  BirdnetSpecies(
    outputIndex: 6250,
    scientificName: 'Turdus mandarinus',
    nameZh: '乌鸫',
    nameEn: 'Chinese Blackbird',
  ),
  BirdnetSpecies(
    outputIndex: 6329,
    scientificName: 'Urocissa erythroryncha',
    nameZh: '红嘴蓝鹊',
    nameEn: 'Red-billed Blue-Magpie',
  ),
];
