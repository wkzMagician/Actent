import 'package:dartloom_messaging/dartloom_messaging.dart' as capability;

typedef MessagingPacket = capability.Packet;
typedef PacketValidationException = capability.PacketValidationException;
typedef PacketValidator = capability.PacketValidator;

const messagingPacketSchemaVersion = capability.messagingCapabilityVersion;
