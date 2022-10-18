import 'dart:io';

class DeliveriesState {
  static List<DeliveryItem> current = List.empty();
}

class DeliveriesUpdated {
  final List<DeliveryItem> deliveries;

  DeliveriesUpdated(this.deliveries);
}

class DeliveryItem {
  final String? labelUrl;
  final bool labelCreated;
  final bool shipped;
  final String orderNumber;

  DeliveryItem(
      this.labelUrl, this.labelCreated, this.shipped, this.orderNumber);
}

class DownloadLabel {
  final DeliveryItem item;

  DownloadLabel(this.item);
}

class OpenLabel {
  final File label;
  final String url;

  OpenLabel(this.label, this.url);
}

class CancelShipment {
  final DeliveryItem item;

  CancelShipment(this.item);
}
