enum ExplorationMode {
  child,
  parent;

  String get storageValue => name;

  String get label => switch (this) {
    ExplorationMode.child => '儿童探索',
    ExplorationMode.parent => '家长陪伴',
  };

  static ExplorationMode parse(String? value) => switch (value) {
    'parent' => ExplorationMode.parent,
    _ => ExplorationMode.child,
  };
}
