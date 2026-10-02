import 'agent_location_io.dart'
    if (dart.library.html) 'agent_location_web.dart' as impl;

Future<String?> currentAgentLocation() => impl.currentAgentLocation();
