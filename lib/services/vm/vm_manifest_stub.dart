import 'package:i_can_code/services/vm/vm_manifest.dart';

Future<VmManifest?> loadVmManifest() async => null;

Future<String> loadVmNotices() => Future.error(UnsupportedError('Only a browser has the VM image to read.'));
