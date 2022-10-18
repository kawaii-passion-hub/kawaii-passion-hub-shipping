import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:event_bus/event_bus.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:kawaii_passion_hub_authentication/kawaii_passion_hub_authentication.dart';
import 'package:kawaii_passion_hub_shipping/kawaii_passion_hub_shipping.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'constants.dart' as constants;
import 'package:http/http.dart' as http;

bool initialized = false;

void initialize({bool useEmulator = false}) {
  if (initialized) {
    return;
  }
  initialized = true;

  FirebaseApp shippingApp =
      GetIt.I<FirebaseApp>(instanceName: constants.firebaseAppName);

  if (kDebugMode) {
    FirebaseDatabase.instanceFor(app: shippingApp).setLoggingEnabled(true);
  }

  if (useEmulator) {
    final host = Platform.isAndroid ? '10.0.2.2' : 'localhost';
    //const authPort = 9099;
    const functionsPort = 5001;
    const databasePort = 9000;

    // ignore: avoid_print
    print('Running with orders emulator.');

    //FirebaseAuth.instanceFor(app: ordersApp).useAuthEmulator(host, authPort);
    FirebaseFunctions.instanceFor(app: shippingApp)
        .useFunctionsEmulator(host, functionsPort);
    FirebaseDatabase.instanceFor(app: shippingApp)
        .useDatabaseEmulator(host, databasePort);
  }

  EventBus globalBus = GetIt.I<EventBus>();
  Controller controller = Controller(globalBus, shippingApp);
  GetIt.I.registerSingleton(controller);
  controller.subscribeToEvents();
}

class Controller extends Disposable {
  EventBus globalBus;
  FirebaseApp shippingApp;

  StreamSubscription<UserInformationUpdated>? loginInformation;
  StreamSubscription<DatabaseEvent>? databaseEvent;
  StreamSubscription<DownloadLabel>? downloadSubscribtion;
  String? lastUserJWT;
  bool initializedModel = false;
  final Lock modelInitalizationLock = Lock();
  final Lock authentificationLock = Lock();

  Controller(this.globalBus, this.shippingApp);

  void subscribeToEvents() {
    loginInformation = globalBus.on<UserInformationUpdated>().listen((event) {
      updateAuthentification(event);
    });
    downloadSubscribtion = globalBus.on<DownloadLabel>().listen((event) {
      download(event.item);
    });
  }

  void updateAuthentification(event) async {
    await authentificationLock.synchronized(() async {
      if (event.newUser.isAuthenticated &&
          event.newUser.claims?['whitelisted'] == true &&
          event.newUser.jwt != lastUserJWT) {
        try {
          HttpsCallableResult<String> result =
              await FirebaseFunctions.instanceFor(app: shippingApp)
                  .httpsCallable('authenticate')
                  .call({
            "jwt": event.newUser.jwt,
          });

          lastUserJWT = event.newUser.jwt;

          await FirebaseAuth.instanceFor(app: shippingApp)
              .signInWithCustomToken(result.data);
          await FirebaseAnalytics.instanceFor(app: shippingApp)
              .logLogin(loginMethod: "Custom Token");
          await initializeModel();
        } on FirebaseFunctionsException catch (error) {
          await FirebaseAnalytics.instanceFor(app: shippingApp)
              .logEvent(name: 'AuthError', parameters: {
            'Error': '${error.code}: ${error.message} - ${error.details}',
          });
          if (kDebugMode) {
            print('${error.code}: ${error.message} - ${error.details}');
          }
        }
      }
    });
  }

  Future initializeModel() async {
    if (initializedModel) {
      return;
    }
    await modelInitalizationLock.synchronized(() async {
      initializedModel = true;
      try {
        final ref =
            FirebaseDatabase.instanceFor(app: shippingApp).ref('orders');
        databaseEvent = ref.onValue.listen((event) {
          processDatabaseSnapshot(event.snapshot);
        });
      } on PlatformException catch (error) {
        await FirebaseAnalytics.instanceFor(app: shippingApp)
            .logEvent(name: 'DatabaseAccessError', parameters: {
          'Error': '${error.code}: ${error.message} - ${error.details}',
        });
        if (kDebugMode) {
          print('${error.code}: ${error.message} - ${error.details}');
        }
        return;
      }
    });
  }

  void processDatabaseSnapshot(DataSnapshot snapshot) {
    if (!snapshot.exists) {
      return;
    }

    final deliveries = (snapshot.value) as Map;
    List<DeliveryItem> deliveryItems = List.empty(growable: true);
    for (var key in deliveries.keys) {
      Map delivery = deliveries[key];
      DeliveryItem item = DeliveryItem(
          delivery.containsKey('labelUrl') ? delivery['labelUrl'] : null,
          delivery.containsKey('labelUrl'),
          delivery['deliveryState'] == 'Shipped',
          delivery['orderNumber']);
      deliveryItems.add(item);
    }

    DeliveriesState.current = deliveryItems;
    globalBus.fire(DeliveriesUpdated(deliveryItems));
  }

  Future download(DeliveryItem item) async {
    File downloaded = await loadPdfFromNetwork(item.labelUrl!);
    globalBus.fire(OpenLabel(downloaded, item.labelUrl!));
  }

  Future<File> loadPdfFromNetwork(String url) async {
    final response = await http.get(Uri.parse(url));
    final bytes = response.bodyBytes;
    return _storeFile(url, bytes);
  }

  Future<File> _storeFile(String url, List<int> bytes) async {
    final filename = basename(url);
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    if (kDebugMode) {
      print('$file');
    }
    return file;
  }

  @override
  FutureOr onDispose() {
    loginInformation?.cancel();
    databaseEvent?.cancel();
    downloadSubscribtion?.cancel();
  }
}
