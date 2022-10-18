import 'dart:async';
import 'dart:io';

import 'package:event_bus/event_bus.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/framework.dart';
import 'package:get_it/get_it.dart';
import 'package:kawaii_passion_hub_orders/kawaii_passion_hub_orders.dart';
import 'package:kawaii_passion_hub_shipping/kawaii_passion_hub_shipping.dart';
import 'package:kawaii_passion_hub_shipping/pdf_viewer_page.dart';
import 'constants.dart' as constants;

bool uiInitialized = false;

void initializeUi() {
  if (uiInitialized) {
    return;
  }
  uiInitialized = true;

  EventBus globalBus = GetIt.I<EventBus>();
  FirebaseApp shippingApp =
      GetIt.I<FirebaseApp>(instanceName: constants.firebaseAppName);
  UiController controller = UiController(globalBus, shippingApp);
  GetIt.I.registerSingleton(controller);
  controller.registerEvents();
}

class UiController extends Disposable {
  EventBus globalBus;
  FirebaseApp shippingApp;
  StreamSubscription<OrderDetailsToolbarExtensionQuery>?
      detailsToolbarExtensionsSubscription;
  StreamSubscription<OpenLabel>? openLabelViewSubscribtion;

  UiController(this.globalBus, this.shippingApp);

  void registerEvents() {
    detailsToolbarExtensionsSubscription = globalBus
        .on<OrderDetailsToolbarExtensionQuery>()
        .listen(registerShippingButtons);
    openLabelViewSubscribtion = globalBus.on<OpenLabel>().listen((event) {
      openLabelFile(event.label, event.url);
    });
  }

  void registerShippingButtons(OrderDetailsToolbarExtensionQuery event) {
    event.register((context, orderId) => StreamBuilder(
          stream: globalBus.on<DeliveriesUpdated>(),
          initialData: DeliveriesUpdated(DeliveriesState.current),
          builder: (context, snapshot) {
            if (!snapshot.hasData ||
                !snapshot.data!.deliveries
                    .any((element) => element.orderNumber == orderId)) {
              return const SizedBox.shrink();
            }

            DeliveryItem item = snapshot.data!.deliveries
                .firstWhere((element) => element.orderNumber == orderId);
            if (item.labelCreated) {
              return const SizedBox.shrink();
            }

            return IconButton(
              onPressed: () => showDialog(
                context: context,
                builder: (dialogContext) {
                  return CreateLabelConfirmation(item, globalBus);
                },
              ),
              icon: const Icon(Icons.send),
              tooltip: "Create shipment label",
            );
          },
        ));

    event.register((context, orderId) => StreamBuilder(
          stream: globalBus.on<DeliveriesUpdated>(),
          initialData: DeliveriesUpdated(DeliveriesState.current),
          builder: (context, snapshot) {
            if (!snapshot.hasData ||
                !snapshot.data!.deliveries
                    .any((element) => element.orderNumber == orderId)) {
              return const SizedBox.shrink();
            }

            DeliveryItem item = snapshot.data!.deliveries
                .firstWhere((element) => element.orderNumber == orderId);
            if (!item.labelCreated || item.labelUrl == null) {
              return const SizedBox.shrink();
            }

            return IconButton(
              onPressed: () => globalBus.fire(DownloadLabel(item)),
              icon: const Icon(Icons.download),
              tooltip: "Download shipment label",
            );
          },
        ));

    event.register((context, orderId) => StreamBuilder(
          stream: globalBus.on<DeliveriesUpdated>(),
          initialData: DeliveriesUpdated(DeliveriesState.current),
          builder: (context, snapshot) {
            if (!snapshot.hasData ||
                !snapshot.data!.deliveries
                    .any((element) => element.orderNumber == orderId)) {
              return const SizedBox.shrink();
            }

            DeliveryItem item = snapshot.data!.deliveries
                .firstWhere((element) => element.orderNumber == orderId);
            if (!item.labelCreated || item.labelUrl == null) {
              return const SizedBox.shrink();
            }

            return IconButton(
              onPressed: () => globalBus.fire(CancelShipment(item)),
              icon: const Icon(Icons.cancel_schedule_send),
              tooltip: "Cancel shipment label",
            );
          },
        ));
  }

  void openLabelFile(File label, String url) {
    NavigationService().navigateTo(
      MaterialPageRoute(
        builder: (context) => PdfViewerPage(
          file: label,
          url: url,
        ),
      ),
    );
  }

  @override
  FutureOr onDispose() {
    detailsToolbarExtensionsSubscription?.cancel();
    openLabelViewSubscribtion?.cancel();
  }
}

class CreateLabelConfirmation extends StatelessWidget {
  final DeliveryItem item;
  final EventBus globalBus;

  const CreateLabelConfirmation(this.item, this.globalBus, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
