/// Collect an element into a [List], returning the same List.
List<T> Function(List<T>, T) intoList<T>() {
  return (list, item) {
    list.add(item);
    return list;
  };
}

/// Collect an element into a [Set], returning the same Set.
Set<T> Function(Set<T>, T) intoSet<T>() {
  return (list, item) {
    list.add(item);
    return list;
  };
}
