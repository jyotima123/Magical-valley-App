import 'package:mvc_app/flavour_config.dart';
import 'main.dart' as main_app;

Future<void> main() async {
  FlavorConfig.appFlavor = Flavor.production;
  await main_app.main();
}
