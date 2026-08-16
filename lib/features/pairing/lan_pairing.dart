// Temporary TLS pairing transport is owned by the generic pairing capability.
// Pigeon supplies only the application callback that persists a successfully
// verified acceptance.
export 'package:dartloom_pairing/lan_pairing.dart'
    show
        LanPairingClient,
        LanPairingRequestHandler,
        LanPairingServer,
        LanPairingService;
