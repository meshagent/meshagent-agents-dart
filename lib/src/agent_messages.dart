import 'dart:convert';
import 'dart:typed_data';

import 'package:meshagent/meshagent.dart';
import 'package:uuid/uuid.dart';

const String agentRoomMessageType = 'agent-message';
const String agentTurnStartType = 'meshagent.agent.turn.start';
const String agentTurnSteerType = 'meshagent.agent.turn.steer';
const String agentTurnInterruptType = 'meshagent.agent.turn.interrupt';
const String agentThreadClearType = 'meshagent.agent.thread.clear';
const String agentRealtimeAudioChunkType =
    'meshagent.agent.realtime_audio.chunk';
const String agentRealtimeAudioCommitType =
    'meshagent.agent.realtime_audio.commit';
const String agentThreadStartType = 'meshagent.agent.thread.start';
const String agentThreadStartedType = 'meshagent.agent.thread.started';
const String agentThreadStartRejectedType =
    'meshagent.agent.thread.start.rejected';
const String agentThreadOpenType = 'meshagent.agent.thread.open';
const String agentThreadCloseType = 'meshagent.agent.thread.close';
const String agentThreadDeleteType = 'meshagent.agent.thread.delete';
const String agentThreadRenameType = 'meshagent.agent.thread.rename';
const String agentCapabilitiesRequestType =
    'meshagent.agent.capabilities_request';
const String agentCapabilitiesResponseType =
    'meshagent.agent.capabilities_response';
const String agentModelsRequestType = 'meshagent.agent.models.request';
const String agentModelsResponseType = 'meshagent.agent.models.response';
const String agentModelChangeType = 'meshagent.agent.model.change';
const String agentModelChangedType = 'meshagent.agent.model.changed';
const String agentThreadClearedType = 'meshagent.agent.thread.cleared';
const String agentTurnStartAcceptedType = 'meshagent.agent.turn.start.accepted';
const String agentTurnStartRejectedType = 'meshagent.agent.turn.start.rejected';
const String agentTurnInterruptAcceptedType =
    'meshagent.agent.turn.interrupt.accepted';
const String agentTurnInterruptedType = 'meshagent.agent.turn.interrupted';
const String agentTurnSteerAcceptedType = 'meshagent.agent.turn.steer.accepted';
const String agentTurnSteeredType = 'meshagent.agent.turn.steered';
const String agentTurnSteerRejectedType = 'meshagent.agent.turn.steer.rejected';
const String agentTurnStartedType = 'meshagent.agent.turn.started';
const String agentTurnEndedType = 'meshagent.agent.turn.ended';
const String agentReasoningContentStartedType =
    'meshagent.agent.reasoning_content.started';
const String agentReasoningContentDeltaType =
    'meshagent.agent.reasoning_content.delta';
const String agentReasoningContentEndedType =
    'meshagent.agent.reasoning_content.ended';
const String agentTextContentStartedType =
    'meshagent.agent.text_content.started';
const String agentTextContentDeltaType = 'meshagent.agent.text_content.delta';
const String agentTextContentEndedType = 'meshagent.agent.text_content.ended';
const String agentFileContentStartedType =
    'meshagent.agent.file_content.started';
const String agentFileContentDeltaType = 'meshagent.agent.file_content.delta';
const String agentFileContentEndedType = 'meshagent.agent.file_content.ended';
const String agentToolCallPendingType = 'meshagent.agent.tool_call.pending';
const String agentToolCallInProgressType =
    'meshagent.agent.tool_call.in_progress';
const String agentToolCallStartedType = 'meshagent.agent.tool_call.started';
const String agentToolCallArgumentsDeltaType =
    'meshagent.agent.tool_call.arguments_delta';
const String agentToolCallLogDeltaType = 'meshagent.agent.tool_call.log_delta';
const String agentToolCallEndedType = 'meshagent.agent.tool_call.ended';
const String agentToolCallApprovalRequestedType =
    'meshagent.agent.tool_call.approval_requested';
const String agentThreadStatusType = 'meshagent.agent.thread.status';
const String agentThreadEventType = 'meshagent.agent.thread.event';
const String agentImageGenerationStartedType =
    'meshagent.agent.image_generation.started';
const String agentImageGenerationPartialType =
    'meshagent.agent.image_generation.partial';
const String agentImageGenerationCompletedType =
    'meshagent.agent.image_generation.completed';
const String agentImageGenerationFailedType =
    'meshagent.agent.image_generation.failed';
const String agentAudioGenerationStartedType =
    'meshagent.agent.audio_generation.started';
const String agentAudioGenerationDeltaType =
    'meshagent.agent.audio_generation.delta';
const String agentAudioGenerationCompletedType =
    'meshagent.agent.audio_generation.completed';
const String agentAudioGenerationFailedType =
    'meshagent.agent.audio_generation.failed';
const String agentAudioTranscriptionStartedType =
    'meshagent.agent.audio_transcription.started';
const String agentAudioTranscriptionDeltaType =
    'meshagent.agent.audio_transcription.delta';
const String agentAudioTranscriptionCompletedType =
    'meshagent.agent.audio_transcription.completed';
const String agentAudioTranscriptionFailedType =
    'meshagent.agent.audio_transcription.failed';
const String agentAudioInputSpeechStartedType =
    'meshagent.agent.audio_input.speech_started';
const String agentAudioInputSpeechEndedType =
    'meshagent.agent.audio_input.speech_ended';
const String agentContextCompactedType = 'meshagent.agent.context.compacted';
const String agentUsageUpdatedType = 'meshagent.agent.usage.updated';
const String agentToolApproveType = 'meshagent.agent.tool_call.approve';
const String agentToolRejectType = 'meshagent.agent.tool_call.reject';

typedef AgentPayload = Map<String, dynamic>;

abstract class AgentMessage {
  AgentMessage({required this.type, String? messageId, this.senderName})
    : messageId = messageId == null || messageId.trim().isEmpty
          ? const Uuid().v4()
          : messageId.trim();

  final String type;
  final String messageId;
  final String? senderName;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    'message_id': messageId,
    if (senderName != null) 'sender_name': senderName,
  };

  static AgentMessage fromJson(Map<String, dynamic> json) {
    final type = json['type'];
    if (type is! String || type.trim().isEmpty) {
      throw ArgumentError.value(json, 'json', "missing string field 'type'");
    }
    switch (type) {
      case agentThreadStartType:
        return StartThread.fromJson(json);
      case agentTurnStartType:
        return TurnStart.fromJson(json);
      case agentTurnSteerType:
        return TurnSteer.fromJson(json);
      case agentTurnInterruptType:
        return TurnInterrupt.fromJson(json);
      case agentRealtimeAudioChunkType:
        return AgentRealtimeAudioChunk.fromJson(json);
      case agentRealtimeAudioCommitType:
        return AgentRealtimeAudioCommit.fromJson(json);
      case agentThreadClearType:
        return ClearThread.fromJson(json);
      case agentThreadOpenType:
        return OpenThread.fromJson(json);
      case agentThreadCloseType:
        return CloseThread.fromJson(json);
      case agentThreadDeleteType:
        return DeleteThread.fromJson(json);
      case agentThreadRenameType:
        return RenameThread.fromJson(json);
      case agentCapabilitiesRequestType:
        return CapabilitiesRequest.fromJson(json);
      case agentCapabilitiesResponseType:
        return CapabilitiesResponse.fromJson(json);
      case agentModelsRequestType:
        return ModelsRequest.fromJson(json);
      case agentModelsResponseType:
        return ModelsResponse.fromJson(json);
      case agentModelChangeType:
        return ChangeModel.fromJson(json);
      case agentModelChangedType:
        return AgentModelChanged.fromJson(json);
      case agentThreadClearedType:
        return ThreadCleared.fromJson(json);
      case agentTurnStartAcceptedType:
        return TurnStartAccepted.fromJson(json);
      case agentTurnStartRejectedType:
        return TurnStartRejected.fromJson(json);
      case agentTurnInterruptAcceptedType:
        return TurnInterruptAccepted.fromJson(json);
      case agentTurnInterruptedType:
        return TurnInterrupted.fromJson(json);
      case agentTurnSteerAcceptedType:
        return TurnSteerAccepted.fromJson(json);
      case agentTurnSteeredType:
        return TurnSteered.fromJson(json);
      case agentTurnSteerRejectedType:
        return TurnSteerRejected.fromJson(json);
      case agentTurnStartedType:
        return TurnStarted.fromJson(json);
      case agentTurnEndedType:
        return TurnEnded.fromJson(json);
      case agentThreadStartedType:
        return ThreadStarted.fromJson(json);
      case agentThreadStartRejectedType:
        return ThreadStartRejected.fromJson(json);
      case agentReasoningContentStartedType:
        return AgentReasoningContentStarted.fromJson(json);
      case agentReasoningContentDeltaType:
        return AgentReasoningContentDelta.fromJson(json);
      case agentReasoningContentEndedType:
        return AgentReasoningContentEnded.fromJson(json);
      case agentTextContentStartedType:
        return AgentTextContentStarted.fromJson(json);
      case agentTextContentDeltaType:
        return AgentTextContentDelta.fromJson(json);
      case agentTextContentEndedType:
        return AgentTextContentEnded.fromJson(json);
      case agentFileContentStartedType:
        return AgentFileContentStarted.fromJson(json);
      case agentFileContentDeltaType:
        return AgentFileContentDelta.fromJson(json);
      case agentFileContentEndedType:
        return AgentFileContentEnded.fromJson(json);
      case agentToolCallPendingType:
        return AgentToolCallPending.fromJson(json);
      case agentToolCallInProgressType:
        return AgentToolCallInProgress.fromJson(json);
      case agentToolCallStartedType:
        return AgentToolCallStarted.fromJson(json);
      case agentToolCallArgumentsDeltaType:
        return AgentToolCallArgumentsDelta.fromJson(json);
      case agentToolCallLogDeltaType:
        return AgentToolCallLogDelta.fromJson(json);
      case agentToolCallEndedType:
        return AgentToolCallEnded.fromJson(json);
      case agentToolCallApprovalRequestedType:
        return AgentToolCallApprovalRequested.fromJson(json);
      case agentThreadStatusType:
        return AgentThreadStatus.fromJson(json);
      case agentThreadEventType:
        return AgentThreadEvent.fromJson(json);
      case agentImageGenerationStartedType:
        return AgentImageGenerationStarted.fromJson(json);
      case agentImageGenerationPartialType:
        return AgentImageGenerationPartial.fromJson(json);
      case agentImageGenerationCompletedType:
        return AgentImageGenerationCompleted.fromJson(json);
      case agentImageGenerationFailedType:
        return AgentImageGenerationFailed.fromJson(json);
      case agentAudioGenerationStartedType:
        return AgentAudioGenerationStarted.fromJson(json);
      case agentAudioGenerationDeltaType:
        return AgentAudioGenerationDelta.fromJson(json);
      case agentAudioGenerationCompletedType:
        return AgentAudioGenerationCompleted.fromJson(json);
      case agentAudioGenerationFailedType:
        return AgentAudioGenerationFailed.fromJson(json);
      case agentAudioTranscriptionStartedType:
        return AgentAudioTranscriptionStarted.fromJson(json);
      case agentAudioTranscriptionDeltaType:
        return AgentAudioTranscriptionDelta.fromJson(json);
      case agentAudioTranscriptionCompletedType:
        return AgentAudioTranscriptionCompleted.fromJson(json);
      case agentAudioTranscriptionFailedType:
        return AgentAudioTranscriptionFailed.fromJson(json);
      case agentAudioInputSpeechStartedType:
        return AgentAudioInputSpeechStarted.fromJson(json);
      case agentAudioInputSpeechEndedType:
        return AgentAudioInputSpeechEnded.fromJson(json);
      case agentContextCompactedType:
        return AgentContextCompacted.fromJson(json);
      case agentUsageUpdatedType:
        return AgentUsageUpdated.fromJson(json);
      case agentToolApproveType:
        return ApproveAgentToolCall.fromJson(json);
      case agentToolRejectType:
        return RejectAgentToolCall.fromJson(json);
    }
    throw ArgumentError.value(
      type,
      'json[type]',
      'unsupported agent message type',
    );
  }
}

abstract class AgentThreadMessage extends AgentMessage {
  AgentThreadMessage({
    required super.type,
    required this.threadId,
    super.messageId,
    super.senderName,
  });

  final String threadId;

  @override
  Map<String, dynamic> toJson() => super.toJson()..['thread_id'] = threadId;
}

abstract class AgentLLMMessage extends AgentThreadMessage {
  AgentLLMMessage({
    required super.type,
    required super.threadId,
    super.messageId,
    super.senderName,
    this.provider,
    this.model,
  });

  final String? provider;
  final String? model;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
    });
}

class ToolChoice {
  const ToolChoice({required this.toolkitName, required this.toolName});

  final String toolkitName;
  final String toolName;

  factory ToolChoice.fromJson(Map<String, dynamic> json) => ToolChoice(
    toolkitName: json['toolkit_name'] as String,
    toolName: json['tool_name'] as String,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'toolkit_name': toolkitName,
    'tool_name': toolName,
  };
}

class TurnToolkitConfig {
  const TurnToolkitConfig({this.clientOptions});

  final Map<String, dynamic>? clientOptions;

  factory TurnToolkitConfig.fromJson(Map<String, dynamic> json) =>
      TurnToolkitConfig(
        clientOptions: _dynamicMapOrNull(json['client_options']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (clientOptions != null) 'client_options': clientOptions,
  };
}

class StartThread extends AgentMessage {
  StartThread({
    super.messageId,
    super.senderName,
    this.content,
    this.name,
    this.realtimeProtocol,
    this.provider,
    this.model,
    this.voice,
    this.outputModalities,
    this.instructions,
    this.toolkits,
    this.toolChoice,
  }) : super(type: agentThreadStartType);

  final List<AgentInputContent>? content;
  final String? name;
  final String? realtimeProtocol;
  final String? provider;
  final String? model;
  final String? voice;
  final List<String>? outputModalities;
  final String? instructions;
  final Map<String, TurnToolkitConfig>? toolkits;
  final ToolChoice? toolChoice;

  factory StartThread.fromJson(Map<String, dynamic> json) => StartThread(
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    content: _inputContentListOrNull(json['content']),
    name: _stringOrNull(json['name']),
    realtimeProtocol: _stringOrNull(json['realtime_protocol']),
    provider: _stringOrNull(json['provider']),
    model: _stringOrNull(json['model']),
    voice: _stringOrNull(json['voice']),
    outputModalities: _stringListOrNull(json['output_modalities']),
    instructions: _stringOrNull(json['instructions']),
    toolkits: _toolkitsOrNull(json['toolkits']),
    toolChoice: _toolChoiceOrNull(json['tool_choice']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (content != null)
        'content': content!.map((entry) => entry.toJson()).toList(),
      if (name != null) 'name': name,
      if (realtimeProtocol != null) 'realtime_protocol': realtimeProtocol,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (voice != null) 'voice': voice,
      if (outputModalities != null) 'output_modalities': outputModalities,
      if (instructions != null) 'instructions': instructions,
      if (toolkits != null)
        'toolkits': toolkits!.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
    });
}

class TurnStart extends AgentThreadMessage {
  TurnStart({
    required super.threadId,
    super.messageId,
    super.senderName,
    this.turnId,
    List<AgentInputContent>? content,
    this.provider,
    this.model,
    this.voice,
    this.outputModalities,
    this.instructions,
    this.toolkits,
    this.toolChoice,
  }) : content = content ?? <AgentInputContent>[],
       super(type: agentTurnStartType);

  final String? turnId;
  final List<AgentInputContent> content;
  final String? provider;
  final String? model;
  final String? voice;
  final List<String>? outputModalities;
  final String? instructions;
  final Map<String, TurnToolkitConfig>? toolkits;
  final ToolChoice? toolChoice;

  factory TurnStart.fromJson(Map<String, dynamic> json) => TurnStart(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _stringOrNull(json['turn_id']),
    content: _inputContentList(json['content']),
    provider: _stringOrNull(json['provider']),
    model: _stringOrNull(json['model']),
    voice: _stringOrNull(json['voice']),
    outputModalities: _stringListOrNull(json['output_modalities']),
    instructions: _stringOrNull(json['instructions']),
    toolkits: _toolkitsOrNull(json['toolkits']),
    toolChoice: _toolChoiceOrNull(json['tool_choice']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (turnId != null) 'turn_id': turnId,
      'content': content.map((entry) => entry.toJson()).toList(),
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (voice != null) 'voice': voice,
      if (outputModalities != null) 'output_modalities': outputModalities,
      if (instructions != null) 'instructions': instructions,
      if (toolkits != null)
        'toolkits': toolkits!.map(
          (key, value) => MapEntry(key, value.toJson()),
        ),
      if (toolChoice != null) 'tool_choice': toolChoice!.toJson(),
    });
}

class TurnSteer extends AgentThreadMessage {
  TurnSteer({
    required super.threadId,
    required this.turnId,
    required this.content,
    super.messageId,
    super.senderName,
  }) : super(type: agentTurnSteerType);

  final List<AgentInputContent> content;
  final String turnId;

  factory TurnSteer.fromJson(Map<String, dynamic> json) => TurnSteer(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _requiredString(json, 'turn_id'),
    content: _inputContentList(json['content']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'content': content.map((entry) => entry.toJson()).toList(),
      'turn_id': turnId,
    });
}

class TurnInterrupt extends AgentThreadMessage {
  TurnInterrupt({
    required super.threadId,
    required this.turnId,
    super.messageId,
    super.senderName,
  }) : super(type: agentTurnInterruptType);

  final String turnId;

  factory TurnInterrupt.fromJson(Map<String, dynamic> json) => TurnInterrupt(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _requiredString(json, 'turn_id'),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['turn_id'] = turnId;
}

class AgentAudioFormat {
  const AgentAudioFormat({
    this.type = 'audio/pcm',
    this.sampleRate = 24000,
    this.bitrate,
  });

  final String type;
  final int? sampleRate;
  final int? bitrate;

  factory AgentAudioFormat.fromJson(Map<String, dynamic> json) =>
      AgentAudioFormat(
        type: _stringOrNull(json['type']) ?? 'audio/pcm',
        sampleRate: _intOrNull(json['sample_rate']),
        bitrate: _intOrNull(json['bitrate']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'type': type,
    if (sampleRate != null) 'sample_rate': sampleRate,
    if (bitrate != null) 'bitrate': bitrate,
  };
}

class AgentRealtimeAudioChunk extends AgentThreadMessage {
  AgentRealtimeAudioChunk({
    required super.threadId,
    super.messageId,
    super.senderName,
    Uint8List? data,
    AgentAudioFormat? format,
  }) : data = data ?? Uint8List(0),
       format = format ?? const AgentAudioFormat(),
       super(type: agentRealtimeAudioChunkType);

  final Uint8List data;
  final AgentAudioFormat format;

  factory AgentRealtimeAudioChunk.fromJson(Map<String, dynamic> json) =>
      AgentRealtimeAudioChunk(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        data: _bytesOrEmpty(json['data']),
        format: _audioFormatOrDefault(json['format']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (data.isNotEmpty) 'data': base64Encode(data),
      'format': format.toJson(),
    });
}

class AgentRealtimeAudioCommit extends AgentThreadMessage {
  AgentRealtimeAudioCommit({
    required super.threadId,
    super.messageId,
    super.senderName,
    this.turnId,
    this.text,
    this.status,
    this.transcriptionItemId,
  }) : super(type: agentRealtimeAudioCommitType);

  final String? turnId;
  final String? text;
  final String? status;
  final String? transcriptionItemId;

  factory AgentRealtimeAudioCommit.fromJson(Map<String, dynamic> json) =>
      AgentRealtimeAudioCommit(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _stringOrNull(json['turn_id']),
        text: _stringOrNull(json['text']),
        status: _stringOrNull(json['status']),
        transcriptionItemId: _stringOrNull(json['transcription_item_id']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (turnId != null) 'turn_id': turnId,
      if (text != null) 'text': text,
      if (status != null) 'status': status,
      if (transcriptionItemId != null)
        'transcription_item_id': transcriptionItemId,
    });
}

class ClearThread extends AgentThreadMessage {
  ClearThread({required super.threadId, super.messageId, super.senderName})
    : super(type: agentThreadClearType);

  factory ClearThread.fromJson(Map<String, dynamic> json) => ClearThread(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
  );
}

class OpenThread extends AgentThreadMessage {
  OpenThread({required super.threadId, super.messageId, super.senderName})
    : super(type: agentThreadOpenType);

  factory OpenThread.fromJson(Map<String, dynamic> json) => OpenThread(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
  );
}

class CloseThread extends AgentThreadMessage {
  CloseThread({required super.threadId, super.messageId, super.senderName})
    : super(type: agentThreadCloseType);

  factory CloseThread.fromJson(Map<String, dynamic> json) => CloseThread(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
  );
}

class DeleteThread extends AgentThreadMessage {
  DeleteThread({required super.threadId, super.messageId, super.senderName})
    : super(type: agentThreadDeleteType);

  factory DeleteThread.fromJson(Map<String, dynamic> json) => DeleteThread(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
  );
}

class RenameThread extends AgentThreadMessage {
  RenameThread({
    required super.threadId,
    required this.name,
    super.messageId,
    super.senderName,
  }) : super(type: agentThreadRenameType);

  final String name;

  factory RenameThread.fromJson(Map<String, dynamic> json) => RenameThread(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    name: _requiredString(json, 'name'),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['name'] = name;
}

class CapabilitiesRequest extends AgentThreadMessage {
  CapabilitiesRequest({
    required super.threadId,
    super.messageId,
    super.senderName,
  }) : super(type: agentCapabilitiesRequestType);

  factory CapabilitiesRequest.fromJson(Map<String, dynamic> json) =>
      CapabilitiesRequest(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
      );
}

class AgentError {
  const AgentError({required this.message, this.code});

  final String message;
  final String? code;

  factory AgentError.fromJson(Map<String, dynamic> json) => AgentError(
    message: _requiredString(json, 'message'),
    code: _stringOrNull(json['code']),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'message': message,
    if (code != null) 'code': code,
  };
}

class ToolkitToolCapabilities {
  const ToolkitToolCapabilities({
    required this.name,
    this.title,
    this.description,
  });

  final String name;
  final String? title;
  final String? description;

  factory ToolkitToolCapabilities.fromJson(Map<String, dynamic> json) =>
      ToolkitToolCapabilities(
        name: _requiredString(json, 'name'),
        title: _stringOrNull(json['title']),
        description: _stringOrNull(json['description']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
  };
}

class ToolkitCapabilities {
  const ToolkitCapabilities({
    required this.name,
    this.title,
    this.description,
    this.thumbnailUrl,
    this.rules = const <String>[],
    this.clientOptions,
    this.hidden = false,
    this.tools = const <ToolkitToolCapabilities>[],
  });

  final String name;
  final String? title;
  final String? description;
  final String? thumbnailUrl;
  final List<String> rules;
  final Map<String, dynamic>? clientOptions;
  final bool hidden;
  final List<ToolkitToolCapabilities> tools;

  factory ToolkitCapabilities.fromJson(Map<String, dynamic> json) =>
      ToolkitCapabilities(
        name: _requiredString(json, 'name'),
        title: _stringOrNull(json['title']),
        description: _stringOrNull(json['description']),
        thumbnailUrl: _stringOrNull(json['thumbnail_url']),
        rules: _stringList(json['rules']),
        clientOptions: _dynamicMapOrNull(json['client_options']),
        hidden: json['hidden'] == true,
        tools: _objectList(json['tools'], ToolkitToolCapabilities.fromJson),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
    'rules': rules,
    if (clientOptions != null) 'client_options': clientOptions,
    'hidden': hidden,
    'tools': tools.map((entry) => entry.toJson()).toList(),
  };
}

class CapabilitiesResponse extends AgentThreadMessage {
  CapabilitiesResponse({
    required super.threadId,
    required this.sourceMessageId,
    required this.version,
    required this.toolkits,
    super.messageId,
    super.senderName,
  }) : super(type: agentCapabilitiesResponseType);

  final String sourceMessageId;
  final String version;
  final List<ToolkitCapabilities> toolkits;

  factory CapabilitiesResponse.fromJson(Map<String, dynamic> json) =>
      CapabilitiesResponse(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        version: _requiredString(json, 'version'),
        toolkits: _objectList(json['toolkits'], ToolkitCapabilities.fromJson),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'source_message_id': sourceMessageId,
      'version': version,
      'toolkits': toolkits.map((entry) => entry.toJson()).toList(),
    });
}

class AgentModelInfo {
  const AgentModelInfo({
    required this.name,
    this.friendlyName,
    this.description,
    this.contextWindow,
    this.pricing,
    this.modalities = const <String>['text'],
    this.availableVoices = const <String>[],
    this.defaultOutputVoice,
    this.inputFormat,
    this.outputFormat,
    this.turnDetection,
    this.realtimeProtocols = const <String>[],
    this.active = false,
  });

  final String name;
  final String? friendlyName;
  final String? description;
  final int? contextWindow;
  final Map<String, double>? pricing;
  final List<String> modalities;
  final List<String> availableVoices;
  final String? defaultOutputVoice;
  final AgentAudioFormat? inputFormat;
  final AgentAudioFormat? outputFormat;
  final String? turnDetection;
  final List<String> realtimeProtocols;
  final bool active;

  factory AgentModelInfo.fromJson(Map<String, dynamic> json) => AgentModelInfo(
    name: _requiredString(json, 'name'),
    friendlyName: _stringOrNull(json['friendly_name']),
    description: _stringOrNull(json['description']),
    contextWindow: _intOrNull(json['context_window']),
    pricing: _doubleMapOrNull(json['pricing']),
    modalities: _stringList(
      json['modalities'],
      fallback: const <String>['text'],
    ),
    availableVoices: _stringList(json['available_voices']),
    defaultOutputVoice: _stringOrNull(json['default_output_voice']),
    inputFormat: _audioFormatOrNull(json['input_format']),
    outputFormat: _audioFormatOrNull(json['output_format']),
    turnDetection: _stringOrNull(json['turn_detection']),
    realtimeProtocols: _stringList(json['realtime_protocols']),
    active: json['active'] == true,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    if (friendlyName != null) 'friendly_name': friendlyName,
    if (description != null) 'description': description,
    if (contextWindow != null) 'context_window': contextWindow,
    if (pricing != null) 'pricing': pricing,
    'modalities': modalities,
    'available_voices': availableVoices,
    if (defaultOutputVoice != null) 'default_output_voice': defaultOutputVoice,
    if (inputFormat != null) 'input_format': inputFormat!.toJson(),
    if (outputFormat != null) 'output_format': outputFormat!.toJson(),
    if (turnDetection != null) 'turn_detection': turnDetection,
    'realtime_protocols': realtimeProtocols,
    'active': active,
  };
}

class AgentProviderInfo {
  const AgentProviderInfo({
    required this.name,
    required this.friendlyName,
    this.description,
    required this.defaultModel,
    this.models = const <AgentModelInfo>[],
  });

  final String name;
  final String friendlyName;
  final String? description;
  final String defaultModel;
  final List<AgentModelInfo> models;

  factory AgentProviderInfo.fromJson(Map<String, dynamic> json) =>
      AgentProviderInfo(
        name: _requiredString(json, 'name'),
        friendlyName: _requiredString(json, 'friendly_name'),
        description: _stringOrNull(json['description']),
        defaultModel: _requiredString(json, 'default_model'),
        models: _objectList(json['models'], AgentModelInfo.fromJson),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'name': name,
    'friendly_name': friendlyName,
    if (description != null) 'description': description,
    'default_model': defaultModel,
    'models': models.map((entry) => entry.toJson()).toList(),
  };
}

class ModelsRequest extends AgentMessage {
  ModelsRequest({super.messageId, super.senderName})
    : super(type: agentModelsRequestType);

  factory ModelsRequest.fromJson(Map<String, dynamic> json) => ModelsRequest(
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
  );
}

class ModelsResponse extends AgentMessage {
  ModelsResponse({
    required this.sourceMessageId,
    required this.providers,
    super.messageId,
    super.senderName,
  }) : super(type: agentModelsResponseType);

  final String sourceMessageId;
  final List<AgentProviderInfo> providers;

  factory ModelsResponse.fromJson(Map<String, dynamic> json) => ModelsResponse(
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    sourceMessageId: _requiredString(json, 'source_message_id'),
    providers: _objectList(json['providers'], AgentProviderInfo.fromJson),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'source_message_id': sourceMessageId,
      'providers': providers.map((entry) => entry.toJson()).toList(),
    });
}

class ChangeModel extends AgentThreadMessage {
  ChangeModel({
    required super.threadId,
    super.messageId,
    super.senderName,
    this.provider,
    this.model,
    this.voice,
  }) : super(type: agentModelChangeType);

  final String? provider;
  final String? model;
  final String? voice;

  factory ChangeModel.fromJson(Map<String, dynamic> json) => ChangeModel(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    provider: _stringOrNull(json['provider']),
    model: _stringOrNull(json['model']),
    voice: _stringOrNull(json['voice']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (voice != null) 'voice': voice,
    });
}

class AgentModelChanged extends AgentThreadMessage {
  AgentModelChanged({
    required super.threadId,
    required this.provider,
    required this.model,
    super.messageId,
    super.senderName,
    this.sourceMessageId,
    this.voice,
    this.inputFormat,
    this.outputFormat,
    this.turnDetection,
    this.outputModalities = const <String>['text'],
    this.realtimeProtocols = const <String>[],
  }) : super(type: agentModelChangedType);

  final String? sourceMessageId;
  final String provider;
  final String model;
  final String? voice;
  final AgentAudioFormat? inputFormat;
  final AgentAudioFormat? outputFormat;
  final String? turnDetection;
  final List<String> outputModalities;
  final List<String> realtimeProtocols;

  factory AgentModelChanged.fromJson(Map<String, dynamic> json) =>
      AgentModelChanged(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        sourceMessageId: _stringOrNull(json['source_message_id']),
        provider: _requiredString(json, 'provider'),
        model: _requiredString(json, 'model'),
        voice: _stringOrNull(json['voice']),
        inputFormat: _audioFormatOrNull(json['input_format']),
        outputFormat: _audioFormatOrNull(json['output_format']),
        turnDetection: _stringOrNull(json['turn_detection']),
        outputModalities: _stringList(
          json['output_modalities'],
          fallback: const <String>['text'],
        ),
        realtimeProtocols: _stringList(json['realtime_protocols']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (sourceMessageId != null) 'source_message_id': sourceMessageId,
      'provider': provider,
      'model': model,
      if (voice != null) 'voice': voice,
      if (inputFormat != null) 'input_format': inputFormat!.toJson(),
      if (outputFormat != null) 'output_format': outputFormat!.toJson(),
      if (turnDetection != null) 'turn_detection': turnDetection,
      'output_modalities': outputModalities,
      'realtime_protocols': realtimeProtocols,
    });
}

class ThreadCleared extends AgentThreadMessage {
  ThreadCleared({
    required super.threadId,
    required this.sourceMessageId,
    super.messageId,
    super.senderName,
  }) : super(type: agentThreadClearedType);

  final String sourceMessageId;

  factory ThreadCleared.fromJson(Map<String, dynamic> json) => ThreadCleared(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    sourceMessageId: _requiredString(json, 'source_message_id'),
  );

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..['source_message_id'] = sourceMessageId;
}

class TurnStartAccepted extends AgentThreadMessage {
  TurnStartAccepted({
    required super.threadId,
    required this.sourceMessageId,
    super.messageId,
    super.senderName,
    this.turnId,
    List<AgentInputContent>? content,
  }) : content = content ?? <AgentInputContent>[],
       super(type: agentTurnStartAcceptedType);

  final String? turnId;
  final String sourceMessageId;
  final List<AgentInputContent> content;

  factory TurnStartAccepted.fromJson(Map<String, dynamic> json) =>
      TurnStartAccepted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _stringOrNull(json['turn_id']),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        content: _inputContentList(json['content']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (turnId != null) 'turn_id': turnId,
      'source_message_id': sourceMessageId,
      'content': content.map((entry) => entry.toJson()).toList(),
    });
}

class TurnStartRejected extends AgentThreadMessage {
  TurnStartRejected({
    required super.threadId,
    required this.sourceMessageId,
    required this.error,
    super.messageId,
    super.senderName,
  }) : super(type: agentTurnStartRejectedType);

  final String sourceMessageId;
  final AgentError error;

  factory TurnStartRejected.fromJson(Map<String, dynamic> json) =>
      TurnStartRejected(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        error: AgentError.fromJson(_requiredMap(json, 'error')),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'source_message_id': sourceMessageId,
      'error': error.toJson(),
    });
}

class TurnInterruptAccepted extends AgentThreadMessage {
  TurnInterruptAccepted({
    required super.threadId,
    required this.turnId,
    required this.sourceMessageId,
    super.messageId,
    super.senderName,
  }) : super(type: agentTurnInterruptAcceptedType);

  final String turnId;
  final String sourceMessageId;

  factory TurnInterruptAccepted.fromJson(Map<String, dynamic> json) =>
      TurnInterruptAccepted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        sourceMessageId: _requiredString(json, 'source_message_id'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'source_message_id': sourceMessageId,
    });
}

class TurnInterrupted extends TurnInterruptAccepted {
  TurnInterrupted({
    required super.threadId,
    required super.turnId,
    required super.sourceMessageId,
    super.messageId,
    super.senderName,
  });

  factory TurnInterrupted.fromJson(Map<String, dynamic> json) =>
      TurnInterrupted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        sourceMessageId: _requiredString(json, 'source_message_id'),
      );

  @override
  String get type => agentTurnInterruptedType;
}

class TurnSteerAccepted extends TurnStartAccepted {
  TurnSteerAccepted({
    required super.threadId,
    required super.sourceMessageId,
    required String turnId,
    super.messageId,
    super.senderName,
    super.content,
  }) : super(turnId: turnId);

  factory TurnSteerAccepted.fromJson(Map<String, dynamic> json) =>
      TurnSteerAccepted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        content: _inputContentList(json['content']),
      );

  @override
  String get type => agentTurnSteerAcceptedType;
}

class TurnSteered extends TurnInterruptAccepted {
  TurnSteered({
    required super.threadId,
    required super.turnId,
    required super.sourceMessageId,
    super.messageId,
    super.senderName,
  });

  factory TurnSteered.fromJson(Map<String, dynamic> json) => TurnSteered(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _requiredString(json, 'turn_id'),
    sourceMessageId: _requiredString(json, 'source_message_id'),
  );

  @override
  String get type => agentTurnSteeredType;
}

class TurnSteerRejected extends AgentThreadMessage {
  TurnSteerRejected({
    required super.threadId,
    required this.turnId,
    required this.sourceMessageId,
    required this.error,
    super.messageId,
    super.senderName,
  }) : super(type: agentTurnSteerRejectedType);

  final String turnId;
  final String sourceMessageId;
  final AgentError error;

  factory TurnSteerRejected.fromJson(Map<String, dynamic> json) =>
      TurnSteerRejected(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        error: AgentError.fromJson(_requiredMap(json, 'error')),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'source_message_id': sourceMessageId,
      'error': error.toJson(),
    });
}

class TurnStarted extends TurnInterruptAccepted {
  TurnStarted({
    required super.threadId,
    required super.turnId,
    required super.sourceMessageId,
    super.messageId,
    super.senderName,
  });

  factory TurnStarted.fromJson(Map<String, dynamic> json) => TurnStarted(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _requiredString(json, 'turn_id'),
    sourceMessageId: _requiredString(json, 'source_message_id'),
  );

  @override
  String get type => agentTurnStartedType;
}

class TurnEnded extends AgentThreadMessage {
  TurnEnded({
    required super.threadId,
    required this.turnId,
    super.messageId,
    super.senderName,
    this.error,
  }) : super(type: agentTurnEndedType);

  final String turnId;
  final AgentError? error;

  factory TurnEnded.fromJson(Map<String, dynamic> json) => TurnEnded(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    turnId: _requiredString(json, 'turn_id'),
    error: _errorOrNull(json['error']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      if (error != null) 'error': error!.toJson(),
    });
}

class ThreadStarted extends AgentMessage {
  ThreadStarted({
    required this.sourceMessageId,
    required this.threadId,
    super.messageId,
    super.senderName,
    this.realtimeConnection,
  }) : super(type: agentThreadStartedType);

  final String sourceMessageId;
  final String threadId;
  final AgentRealtimeConnectionInfo? realtimeConnection;

  factory ThreadStarted.fromJson(Map<String, dynamic> json) => ThreadStarted(
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    sourceMessageId: _requiredString(json, 'source_message_id'),
    threadId: _requiredString(json, 'thread_id'),
    realtimeConnection: _realtimeConnectionOrNull(json['realtime_connection']),
  );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'source_message_id': sourceMessageId,
      'thread_id': threadId,
      if (realtimeConnection != null)
        'realtime_connection': realtimeConnection!.toJson(),
    });
}

class ThreadStartRejected extends AgentMessage {
  ThreadStartRejected({
    required this.sourceMessageId,
    required this.error,
    super.messageId,
    super.senderName,
  }) : super(type: agentThreadStartRejectedType);

  final String sourceMessageId;
  final AgentError error;

  factory ThreadStartRejected.fromJson(Map<String, dynamic> json) =>
      ThreadStartRejected(
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        sourceMessageId: _requiredString(json, 'source_message_id'),
        error: AgentError.fromJson(_requiredMap(json, 'error')),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'source_message_id': sourceMessageId,
      'error': error.toJson(),
    });
}

class AgentRealtimeConnectionInfo {
  const AgentRealtimeConnectionInfo({
    required this.protocol,
    required this.url,
    this.headers = const <String, String>{},
    this.webOnlyProtocol,
  });

  final String protocol;
  final String url;
  final Map<String, String> headers;
  final String? webOnlyProtocol;

  factory AgentRealtimeConnectionInfo.fromJson(Map<String, dynamic> json) =>
      AgentRealtimeConnectionInfo(
        protocol: _requiredString(json, 'protocol'),
        url: _requiredString(json, 'url'),
        headers: _stringMap(json['headers']),
        webOnlyProtocol: _stringOrNull(json['web_only_protocol']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'protocol': protocol,
    'url': url,
    'headers': headers,
    if (webOnlyProtocol != null) 'web_only_protocol': webOnlyProtocol,
  };
}

abstract class _ContentPartMessage extends AgentLLMMessage {
  _ContentPartMessage({
    required super.type,
    required super.threadId,
    required this.turnId,
    required this.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  });

  final String turnId;
  final String itemId;

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()
        ..addAll(<String, dynamic>{'turn_id': turnId, 'item_id': itemId});
}

class AgentReasoningContentStarted extends _ContentPartMessage {
  AgentReasoningContentStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentReasoningContentStartedType);

  factory AgentReasoningContentStarted.fromJson(Map<String, dynamic> json) =>
      AgentReasoningContentStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );
}

class AgentReasoningContentDelta extends _ContentPartMessage {
  AgentReasoningContentDelta({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required this.text,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentReasoningContentDeltaType);

  final String text;

  factory AgentReasoningContentDelta.fromJson(Map<String, dynamic> json) =>
      AgentReasoningContentDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        text: _requiredString(json, 'text'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['text'] = text;
}

class AgentReasoningContentEnded extends _ContentPartMessage {
  AgentReasoningContentEnded({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentReasoningContentEndedType);

  factory AgentReasoningContentEnded.fromJson(Map<String, dynamic> json) =>
      AgentReasoningContentEnded(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );
}

class AgentTextContentStarted extends _ContentPartMessage {
  AgentTextContentStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.phase,
  }) : super(type: agentTextContentStartedType);

  final String? phase;

  factory AgentTextContentStarted.fromJson(Map<String, dynamic> json) =>
      AgentTextContentStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        phase: _stringOrNull(json['phase']),
      );

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()
        ..addAll(<String, dynamic>{if (phase != null) 'phase': phase});
}

class AgentTextContentDelta extends AgentTextContentStarted {
  AgentTextContentDelta({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required this.text,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.phase,
  });

  final String text;

  factory AgentTextContentDelta.fromJson(Map<String, dynamic> json) =>
      AgentTextContentDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        text: _requiredString(json, 'text'),
        phase: _stringOrNull(json['phase']),
      );

  @override
  String get type => agentTextContentDeltaType;

  @override
  Map<String, dynamic> toJson() => super.toJson()..['text'] = text;
}

class AgentTextContentEnded extends AgentTextContentStarted {
  AgentTextContentEnded({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.phase,
  });

  factory AgentTextContentEnded.fromJson(Map<String, dynamic> json) =>
      AgentTextContentEnded(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        phase: _stringOrNull(json['phase']),
      );

  @override
  String get type => agentTextContentEndedType;
}

class AgentFileContentStarted extends _ContentPartMessage {
  AgentFileContentStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentFileContentStartedType);

  factory AgentFileContentStarted.fromJson(Map<String, dynamic> json) =>
      AgentFileContentStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );
}

class AgentFileContentDelta extends _ContentPartMessage {
  AgentFileContentDelta({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required this.url,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentFileContentDeltaType);

  final String url;

  factory AgentFileContentDelta.fromJson(Map<String, dynamic> json) =>
      AgentFileContentDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        url: _requiredString(json, 'url'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['url'] = url;
}

class AgentFileContentEnded extends _ContentPartMessage {
  AgentFileContentEnded({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentFileContentEndedType);

  factory AgentFileContentEnded.fromJson(Map<String, dynamic> json) =>
      AgentFileContentEnded(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );
}

abstract class _ToolCallStateMessage extends AgentLLMMessage {
  _ToolCallStateMessage({
    required super.type,
    required super.threadId,
    required this.turnId,
    required this.itemId,
    required this.toolkit,
    required this.tool,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.namespace = 'meshagent',
    this.callId,
    this.arguments,
    this.argumentBytes,
  });

  final String turnId;
  final String itemId;
  final String namespace;
  final String? callId;
  final String toolkit;
  final String tool;
  final Map<String, dynamic>? arguments;
  final int? argumentBytes;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'item_id': itemId,
      'namespace': namespace,
      if (callId != null) 'call_id': callId,
      'toolkit': toolkit,
      'tool': tool,
      if (arguments != null) 'arguments': arguments,
      if (argumentBytes != null) 'argument_bytes': argumentBytes,
    });
}

class AgentToolCallPending extends _ToolCallStateMessage {
  AgentToolCallPending({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required super.toolkit,
    required super.tool,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.namespace,
    super.callId,
    super.arguments,
    super.argumentBytes,
  }) : super(type: agentToolCallPendingType);

  factory AgentToolCallPending.fromJson(Map<String, dynamic> json) =>
      AgentToolCallPending(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        toolkit: _requiredString(json, 'toolkit'),
        tool: _requiredString(json, 'tool'),
        arguments: _dynamicMapOrNull(json['arguments']),
        argumentBytes: _intOrNull(json['argument_bytes']),
      );
}

class AgentToolCallInProgress extends AgentToolCallPending {
  AgentToolCallInProgress({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required super.toolkit,
    required super.tool,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.namespace,
    super.callId,
    super.arguments,
    super.argumentBytes,
  });

  factory AgentToolCallInProgress.fromJson(Map<String, dynamic> json) =>
      AgentToolCallInProgress(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        toolkit: _requiredString(json, 'toolkit'),
        tool: _requiredString(json, 'tool'),
        arguments: _dynamicMapOrNull(json['arguments']),
        argumentBytes: _intOrNull(json['argument_bytes']),
      );

  @override
  String get type => agentToolCallInProgressType;
}

class AgentToolCallStarted extends AgentToolCallPending {
  AgentToolCallStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required super.toolkit,
    required super.tool,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.namespace,
    super.callId,
    super.arguments,
    super.argumentBytes,
  });

  factory AgentToolCallStarted.fromJson(Map<String, dynamic> json) =>
      AgentToolCallStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        toolkit: _requiredString(json, 'toolkit'),
        tool: _requiredString(json, 'tool'),
        arguments: _dynamicMapOrNull(json['arguments']),
        argumentBytes: _intOrNull(json['argument_bytes']),
      );

  @override
  String get type => agentToolCallStartedType;
}

class AgentToolCallArgumentsDelta extends AgentLLMMessage {
  AgentToolCallArgumentsDelta({
    required super.threadId,
    required this.turnId,
    required this.itemId,
    required this.delta,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.namespace = 'meshagent',
    this.callId,
  }) : super(type: agentToolCallArgumentsDeltaType);

  final String turnId;
  final String itemId;
  final String namespace;
  final String? callId;
  final String delta;

  factory AgentToolCallArgumentsDelta.fromJson(Map<String, dynamic> json) =>
      AgentToolCallArgumentsDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        delta: _requiredString(json, 'delta'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'item_id': itemId,
      'namespace': namespace,
      if (callId != null) 'call_id': callId,
      'delta': delta,
    });
}

class AgentToolCallLogLine {
  const AgentToolCallLogLine({required this.source, required this.text});

  final String source;
  final String text;

  factory AgentToolCallLogLine.fromJson(Map<String, dynamic> json) =>
      AgentToolCallLogLine(
        source: _requiredString(json, 'source'),
        text: _requiredString(json, 'text'),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'source': source,
    'text': text,
  };
}

class AgentToolCallLogDelta extends AgentLLMMessage {
  AgentToolCallLogDelta({
    required super.threadId,
    required this.turnId,
    required this.itemId,
    required this.lines,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.namespace = 'meshagent',
    this.callId,
  }) : super(type: agentToolCallLogDeltaType);

  final String turnId;
  final String itemId;
  final String namespace;
  final String? callId;
  final List<AgentToolCallLogLine> lines;

  factory AgentToolCallLogDelta.fromJson(Map<String, dynamic> json) =>
      AgentToolCallLogDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        lines: _objectList(json['lines'], AgentToolCallLogLine.fromJson),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'item_id': itemId,
      'namespace': namespace,
      if (callId != null) 'call_id': callId,
      'lines': lines.map((entry) => entry.toJson()).toList(),
    });
}

class AgentToolCallEnded extends AgentLLMMessage {
  AgentToolCallEnded({
    required super.threadId,
    required this.turnId,
    required this.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.namespace = 'meshagent',
    this.callId,
    this.toolkit,
    this.tool,
    this.result,
    this.error,
  }) : super(type: agentToolCallEndedType);

  final String turnId;
  final String itemId;
  final String namespace;
  final String? callId;
  final String? toolkit;
  final String? tool;
  final Content? result;
  final AgentError? error;

  factory AgentToolCallEnded.fromJson(Map<String, dynamic> json) =>
      AgentToolCallEnded(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        toolkit: _stringOrNull(json['toolkit']),
        tool: _stringOrNull(json['tool']),
        result: _contentOrNull(json['result']),
        error: _errorOrNull(json['error']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'item_id': itemId,
      'namespace': namespace,
      if (callId != null) 'call_id': callId,
      if (toolkit != null) 'toolkit': toolkit,
      if (tool != null) 'tool': tool,
      if (result != null) 'result': _contentHeader(result!),
      if (error != null) 'error': error!.toJson(),
    });
}

class AgentToolCallApprovalRequested extends AgentToolCallPending {
  AgentToolCallApprovalRequested({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required super.toolkit,
    required super.tool,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.namespace,
    super.callId,
    super.arguments,
  });

  factory AgentToolCallApprovalRequested.fromJson(Map<String, dynamic> json) =>
      AgentToolCallApprovalRequested(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        namespace: _stringOrNull(json['namespace']) ?? 'meshagent',
        callId: _stringOrNull(json['call_id']),
        toolkit: _requiredString(json, 'toolkit'),
        tool: _requiredString(json, 'tool'),
        arguments: _dynamicMapOrNull(json['arguments']),
      );

  @override
  String get type => agentToolCallApprovalRequestedType;
}

class AgentThreadStatus extends AgentThreadMessage {
  AgentThreadStatus({
    required super.threadId,
    super.messageId,
    super.senderName,
    this.status,
    this.mode,
    this.startedAt,
    this.turnId,
    this.pendingItemId,
    this.totalBytes,
    this.linesAdded,
    this.linesRemoved,
  }) : super(type: agentThreadStatusType);

  final String? status;
  final String? mode;
  final String? startedAt;
  final String? turnId;
  final String? pendingItemId;
  final int? totalBytes;
  final int? linesAdded;
  final int? linesRemoved;

  factory AgentThreadStatus.fromJson(Map<String, dynamic> json) =>
      AgentThreadStatus(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        status: _stringOrNull(json['status']),
        mode: _stringOrNull(json['mode']),
        startedAt: _stringOrNull(json['started_at']),
        turnId: _stringOrNull(json['turn_id']),
        pendingItemId: _stringOrNull(json['pending_item_id']),
        totalBytes: _intOrNull(json['total_bytes']),
        linesAdded: _intOrNull(json['lines_added']),
        linesRemoved: _intOrNull(json['lines_removed']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (status != null) 'status': status,
      if (mode != null) 'mode': mode,
      if (startedAt != null) 'started_at': startedAt,
      if (turnId != null) 'turn_id': turnId,
      if (pendingItemId != null) 'pending_item_id': pendingItemId,
      if (totalBytes != null) 'total_bytes': totalBytes,
      if (linesAdded != null) 'lines_added': linesAdded,
      if (linesRemoved != null) 'lines_removed': linesRemoved,
    });
}

class AgentThreadEvent extends AgentLLMMessage {
  AgentThreadEvent({
    required super.threadId,
    required this.event,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
  }) : super(type: agentThreadEventType);

  final Map<String, dynamic> event;

  factory AgentThreadEvent.fromJson(Map<String, dynamic> json) =>
      AgentThreadEvent(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        event: _requiredMap(json, 'event'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['event'] = event;
}

class AgentGeneratedImage {
  const AgentGeneratedImage({
    this.uri,
    this.mimeType,
    this.createdAt,
    this.createdBy,
    this.width,
    this.height,
    this.status,
  });

  final String? uri;
  final String? mimeType;
  final String? createdAt;
  final String? createdBy;
  final num? width;
  final num? height;
  final String? status;

  factory AgentGeneratedImage.fromJson(Map<String, dynamic> json) =>
      AgentGeneratedImage(
        uri: _stringOrNull(json['uri']),
        mimeType: _stringOrNull(json['mime_type']),
        createdAt: _stringOrNull(json['created_at']),
        createdBy: _stringOrNull(json['created_by']),
        width: _numOrNull(json['width']),
        height: _numOrNull(json['height']),
        status: _stringOrNull(json['status']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (uri != null) 'uri': uri,
    if (mimeType != null) 'mime_type': mimeType,
    if (createdAt != null) 'created_at': createdAt,
    if (createdBy != null) 'created_by': createdBy,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (status != null) 'status': status,
  };
}

abstract class _ImageGenerationMessage extends AgentLLMMessage {
  _ImageGenerationMessage({
    required super.type,
    required super.threadId,
    required this.turnId,
    required this.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.callId,
    this.toolkit = 'image_generation',
    this.tool = 'image_generation',
    this.arguments,
  });

  final String turnId;
  final String itemId;
  final String? callId;
  final String toolkit;
  final String tool;
  final Map<String, dynamic>? arguments;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      'item_id': itemId,
      if (callId != null) 'call_id': callId,
      'toolkit': toolkit,
      'tool': tool,
      if (arguments != null) 'arguments': arguments,
    });
}

class AgentImageGenerationStarted extends _ImageGenerationMessage {
  AgentImageGenerationStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.callId,
    super.toolkit,
    super.tool,
    super.arguments,
  }) : super(type: agentImageGenerationStartedType);

  factory AgentImageGenerationStarted.fromJson(Map<String, dynamic> json) =>
      AgentImageGenerationStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        callId: _stringOrNull(json['call_id']),
        toolkit: _stringOrNull(json['toolkit']) ?? 'image_generation',
        tool: _stringOrNull(json['tool']) ?? 'image_generation',
        arguments: _dynamicMapOrNull(json['arguments']),
      );
}

class AgentImageGenerationPartial extends _ImageGenerationMessage {
  AgentImageGenerationPartial({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.callId,
    super.toolkit,
    super.tool,
    super.arguments,
    this.image,
    this.partialIndex,
  }) : super(type: agentImageGenerationPartialType);

  final AgentGeneratedImage? image;
  final int? partialIndex;

  factory AgentImageGenerationPartial.fromJson(Map<String, dynamic> json) =>
      AgentImageGenerationPartial(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        callId: _stringOrNull(json['call_id']),
        toolkit: _stringOrNull(json['toolkit']) ?? 'image_generation',
        tool: _stringOrNull(json['tool']) ?? 'image_generation',
        arguments: _dynamicMapOrNull(json['arguments']),
        image: _generatedImageOrNull(json['image']),
        partialIndex: _intOrNull(json['partial_index']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (image != null) 'image': image!.toJson(),
      if (partialIndex != null) 'partial_index': partialIndex,
    });
}

class AgentImageGenerationCompleted extends _ImageGenerationMessage {
  AgentImageGenerationCompleted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.callId,
    super.toolkit,
    super.tool,
    super.arguments,
    this.images = const <AgentGeneratedImage>[],
  }) : super(type: agentImageGenerationCompletedType);

  final List<AgentGeneratedImage> images;

  factory AgentImageGenerationCompleted.fromJson(Map<String, dynamic> json) =>
      AgentImageGenerationCompleted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        callId: _stringOrNull(json['call_id']),
        toolkit: _stringOrNull(json['toolkit']) ?? 'image_generation',
        tool: _stringOrNull(json['tool']) ?? 'image_generation',
        arguments: _dynamicMapOrNull(json['arguments']),
        images: _objectList(json['images'], AgentGeneratedImage.fromJson),
      );

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()
        ..['images'] = images.map((entry) => entry.toJson()).toList();
}

class AgentImageGenerationFailed extends _ImageGenerationMessage {
  AgentImageGenerationFailed({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.callId,
    super.toolkit,
    super.tool,
    super.arguments,
    this.error,
  }) : super(type: agentImageGenerationFailedType);

  final AgentError? error;

  factory AgentImageGenerationFailed.fromJson(Map<String, dynamic> json) =>
      AgentImageGenerationFailed(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        callId: _stringOrNull(json['call_id']),
        toolkit: _stringOrNull(json['toolkit']) ?? 'image_generation',
        tool: _stringOrNull(json['tool']) ?? 'image_generation',
        arguments: _dynamicMapOrNull(json['arguments']),
        error: _errorOrNull(json['error']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{if (error != null) 'error': error!.toJson()});
}

class AgentGeneratedAudio {
  const AgentGeneratedAudio({
    this.uri,
    this.mimeType,
    this.createdAt,
    this.createdBy,
    this.status,
    this.transcript,
  });

  final String? uri;
  final String? mimeType;
  final String? createdAt;
  final String? createdBy;
  final String? status;
  final String? transcript;

  factory AgentGeneratedAudio.fromJson(Map<String, dynamic> json) =>
      AgentGeneratedAudio(
        uri: _stringOrNull(json['uri']),
        mimeType: _stringOrNull(json['mime_type']),
        createdAt: _stringOrNull(json['created_at']),
        createdBy: _stringOrNull(json['created_by']),
        status: _stringOrNull(json['status']),
        transcript: _stringOrNull(json['transcript']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    if (uri != null) 'uri': uri,
    if (mimeType != null) 'mime_type': mimeType,
    if (createdAt != null) 'created_at': createdAt,
    if (createdBy != null) 'created_by': createdBy,
    if (status != null) 'status': status,
    if (transcript != null) 'transcript': transcript,
  };
}

abstract class _AudioGenerationMessage extends _ContentPartMessage {
  _AudioGenerationMessage({
    required super.type,
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    this.responseId,
    this.contentIndex,
  });

  final String? responseId;
  final int? contentIndex;

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (responseId != null) 'response_id': responseId,
      if (contentIndex != null) 'content_index': contentIndex,
    });
}

class AgentAudioGenerationStarted extends _AudioGenerationMessage {
  AgentAudioGenerationStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
  }) : super(type: agentAudioGenerationStartedType);

  factory AgentAudioGenerationStarted.fromJson(Map<String, dynamic> json) =>
      AgentAudioGenerationStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
      );
}

class AgentAudioGenerationDelta extends _AudioGenerationMessage {
  AgentAudioGenerationDelta({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    Uint8List? data,
    this.mimeType,
    this.outputFormat,
  }) : data = data ?? Uint8List(0),
       super(type: agentAudioGenerationDeltaType);

  final Uint8List data;
  final String? mimeType;
  final AgentAudioFormat? outputFormat;

  factory AgentAudioGenerationDelta.fromJson(Map<String, dynamic> json) =>
      AgentAudioGenerationDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        data: _bytesOrEmpty(json['data']),
        mimeType: _stringOrNull(json['mime_type']),
        outputFormat: _audioFormatOrNull(json['output_format']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (data.isNotEmpty) 'data': base64Encode(data),
      if (mimeType != null) 'mime_type': mimeType,
      if (outputFormat != null) 'output_format': outputFormat!.toJson(),
    });
}

class AgentAudioGenerationCompleted extends _AudioGenerationMessage {
  AgentAudioGenerationCompleted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    this.audio,
    this.outputFormat,
  }) : super(type: agentAudioGenerationCompletedType);

  final AgentGeneratedAudio? audio;
  final AgentAudioFormat? outputFormat;

  factory AgentAudioGenerationCompleted.fromJson(Map<String, dynamic> json) =>
      AgentAudioGenerationCompleted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        audio: _generatedAudioOrNull(json['audio']),
        outputFormat: _audioFormatOrNull(json['output_format']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (audio != null) 'audio': audio!.toJson(),
      if (outputFormat != null) 'output_format': outputFormat!.toJson(),
    });
}

class AgentAudioGenerationFailed extends _AudioGenerationMessage {
  AgentAudioGenerationFailed({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    this.error,
  }) : super(type: agentAudioGenerationFailedType);

  final AgentError? error;

  factory AgentAudioGenerationFailed.fromJson(Map<String, dynamic> json) =>
      AgentAudioGenerationFailed(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        error: _errorOrNull(json['error']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{if (error != null) 'error': error!.toJson()});
}

abstract class _AudioTranscriptionMessage extends _AudioGenerationMessage {
  _AudioTranscriptionMessage({
    required super.type,
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    this.role,
  });

  final String? role;

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll(<String, dynamic>{if (role != null) 'role': role});
}

class AgentAudioTranscriptionStarted extends _AudioTranscriptionMessage {
  AgentAudioTranscriptionStarted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    super.role,
  }) : super(type: agentAudioTranscriptionStartedType);

  factory AgentAudioTranscriptionStarted.fromJson(Map<String, dynamic> json) =>
      AgentAudioTranscriptionStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        role: _stringOrNull(json['role']),
      );
}

class AgentAudioTranscriptionDelta extends _AudioTranscriptionMessage {
  AgentAudioTranscriptionDelta({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    required this.text,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    super.role,
  }) : super(type: agentAudioTranscriptionDeltaType);

  final String text;

  factory AgentAudioTranscriptionDelta.fromJson(Map<String, dynamic> json) =>
      AgentAudioTranscriptionDelta(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        role: _stringOrNull(json['role']),
        text: _requiredString(json, 'text'),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()..['text'] = text;
}

class AgentAudioTranscriptionCompleted extends _AudioTranscriptionMessage {
  AgentAudioTranscriptionCompleted({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    super.role,
    this.text,
  }) : super(type: agentAudioTranscriptionCompletedType);

  final String? text;

  factory AgentAudioTranscriptionCompleted.fromJson(
    Map<String, dynamic> json,
  ) => AgentAudioTranscriptionCompleted(
    threadId: _requiredString(json, 'thread_id'),
    messageId: _stringOrNull(json['message_id']),
    senderName: _stringOrNull(json['sender_name']),
    provider: _stringOrNull(json['provider']),
    model: _stringOrNull(json['model']),
    turnId: _requiredString(json, 'turn_id'),
    itemId: _requiredString(json, 'item_id'),
    responseId: _stringOrNull(json['response_id']),
    contentIndex: _intOrNull(json['content_index']),
    role: _stringOrNull(json['role']),
    text: _stringOrNull(json['text']),
  );

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()..addAll(<String, dynamic>{if (text != null) 'text': text});
}

class AgentAudioTranscriptionFailed extends _AudioTranscriptionMessage {
  AgentAudioTranscriptionFailed({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
    super.provider,
    super.model,
    super.responseId,
    super.contentIndex,
    super.role,
    this.error,
  }) : super(type: agentAudioTranscriptionFailedType);

  final AgentError? error;

  factory AgentAudioTranscriptionFailed.fromJson(Map<String, dynamic> json) =>
      AgentAudioTranscriptionFailed(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        provider: _stringOrNull(json['provider']),
        model: _stringOrNull(json['model']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
        responseId: _stringOrNull(json['response_id']),
        contentIndex: _intOrNull(json['content_index']),
        role: _stringOrNull(json['role']),
        error: _errorOrNull(json['error']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{if (error != null) 'error': error!.toJson()});
}

class AgentAudioInputSpeechStarted extends AgentThreadMessage {
  AgentAudioInputSpeechStarted({
    required super.threadId,
    required this.turnId,
    super.messageId,
    super.senderName,
    this.itemId,
    this.audioStartMs,
  }) : super(type: agentAudioInputSpeechStartedType);

  final String turnId;
  final String? itemId;
  final int? audioStartMs;

  factory AgentAudioInputSpeechStarted.fromJson(Map<String, dynamic> json) =>
      AgentAudioInputSpeechStarted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _stringOrNull(json['item_id']),
        audioStartMs: _intOrNull(json['audio_start_ms']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      if (itemId != null) 'item_id': itemId,
      if (audioStartMs != null) 'audio_start_ms': audioStartMs,
    });
}

class AgentAudioInputSpeechEnded extends AgentThreadMessage {
  AgentAudioInputSpeechEnded({
    required super.threadId,
    required this.turnId,
    super.messageId,
    super.senderName,
    this.itemId,
    this.audioEndMs,
  }) : super(type: agentAudioInputSpeechEndedType);

  final String turnId;
  final String? itemId;
  final int? audioEndMs;

  factory AgentAudioInputSpeechEnded.fromJson(Map<String, dynamic> json) =>
      AgentAudioInputSpeechEnded(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _stringOrNull(json['item_id']),
        audioEndMs: _intOrNull(json['audio_end_ms']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'turn_id': turnId,
      if (itemId != null) 'item_id': itemId,
      if (audioEndMs != null) 'audio_end_ms': audioEndMs,
    });
}

class AgentContextCompacted extends AgentThreadMessage {
  AgentContextCompacted({
    required super.threadId,
    required this.checkpointId,
    required this.path,
    required this.throughSequence,
    super.messageId,
    super.senderName,
    this.createdAt,
    this.messages,
  }) : super(type: agentContextCompactedType);

  final String checkpointId;
  final String path;
  final int throughSequence;
  final String? createdAt;
  final List<Map<String, dynamic>>? messages;

  factory AgentContextCompacted.fromJson(Map<String, dynamic> json) =>
      AgentContextCompacted(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        checkpointId: _requiredString(json, 'checkpoint_id'),
        path: _requiredString(json, 'path'),
        throughSequence: _requiredInt(json, 'through_sequence'),
        createdAt: _stringOrNull(json['created_at']),
        messages: _mapListOrNull(json['messages']),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      'checkpoint_id': checkpointId,
      'path': path,
      'through_sequence': throughSequence,
      if (createdAt != null) 'created_at': createdAt,
      if (messages != null) 'messages': messages,
    });
}

class AgentContextWindowUsage {
  const AgentContextWindowUsage({
    required this.usedTokens,
    this.totalTokens,
    this.compactionMode,
    this.compactionThreshold,
  });

  final int usedTokens;
  final int? totalTokens;
  final String? compactionMode;
  final int? compactionThreshold;

  factory AgentContextWindowUsage.fromJson(Map<String, dynamic> json) =>
      AgentContextWindowUsage(
        usedTokens: _requiredInt(json, 'used_tokens'),
        totalTokens: _intOrNull(json['total_tokens']),
        compactionMode: _stringOrNull(json['compaction_mode']),
        compactionThreshold: _intOrNull(json['compaction_threshold']),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'used_tokens': usedTokens,
    if (totalTokens != null) 'total_tokens': totalTokens,
    if (compactionMode != null) 'compaction_mode': compactionMode,
    if (compactionThreshold != null)
      'compaction_threshold': compactionThreshold,
  };
}

class AgentUsageUpdated extends AgentThreadMessage {
  AgentUsageUpdated({
    required super.threadId,
    required this.contextWindow,
    super.messageId,
    super.senderName,
    this.turnId,
    this.usage = const <String, double>{},
  }) : super(type: agentUsageUpdatedType);

  final String? turnId;
  final Map<String, double> usage;
  final AgentContextWindowUsage contextWindow;

  factory AgentUsageUpdated.fromJson(Map<String, dynamic> json) =>
      AgentUsageUpdated(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _stringOrNull(json['turn_id']),
        usage: _doubleMap(json['usage']),
        contextWindow: AgentContextWindowUsage.fromJson(
          _requiredMap(json, 'context_window'),
        ),
      );

  @override
  Map<String, dynamic> toJson() => super.toJson()
    ..addAll(<String, dynamic>{
      if (turnId != null) 'turn_id': turnId,
      'usage': usage,
      'context_window': contextWindow.toJson(),
    });
}

class ApproveAgentToolCall extends AgentThreadMessage {
  ApproveAgentToolCall({
    required super.threadId,
    required this.turnId,
    required this.itemId,
    super.messageId,
    super.senderName,
  }) : super(type: agentToolApproveType);

  final String turnId;
  final String itemId;

  factory ApproveAgentToolCall.fromJson(Map<String, dynamic> json) =>
      ApproveAgentToolCall(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );

  @override
  Map<String, dynamic> toJson() =>
      super.toJson()
        ..addAll(<String, dynamic>{'turn_id': turnId, 'item_id': itemId});
}

class RejectAgentToolCall extends ApproveAgentToolCall {
  RejectAgentToolCall({
    required super.threadId,
    required super.turnId,
    required super.itemId,
    super.messageId,
    super.senderName,
  });

  factory RejectAgentToolCall.fromJson(Map<String, dynamic> json) =>
      RejectAgentToolCall(
        threadId: _requiredString(json, 'thread_id'),
        messageId: _stringOrNull(json['message_id']),
        senderName: _stringOrNull(json['sender_name']),
        turnId: _requiredString(json, 'turn_id'),
        itemId: _requiredString(json, 'item_id'),
      );

  @override
  String get type => agentToolRejectType;
}

List<AgentInputContent> agentInputContent({
  required String text,
  required List<String> attachments,
}) {
  final content = <AgentInputContent>[];
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) {
    content.add(AgentTextContent(text: text));
  }
  for (final attachment in attachments) {
    final normalized = attachment.trim();
    if (normalized.isNotEmpty) {
      content.add(AgentFileContent(url: normalized));
    }
  }
  return content;
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String) {
    return value;
  }
  throw ArgumentError.value(json, 'json', "missing string field '$key'");
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = _intOrNull(json[key]);
  if (value != null) {
    return value;
  }
  throw ArgumentError.value(json, 'json', "missing integer field '$key'");
}

Map<String, dynamic> _requiredMap(Map<String, dynamic> json, String key) {
  final value = _dynamicMapOrNull(json[key]);
  if (value != null) {
    return value;
  }
  throw ArgumentError.value(json, 'json', "missing object field '$key'");
}

String? _stringOrNull(Object? value) => value is String ? value : null;

int? _intOrNull(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

num? _numOrNull(Object? value) {
  if (value is num) {
    return value;
  }
  if (value is String) {
    return num.tryParse(value);
  }
  return null;
}

Uint8List _bytesOrEmpty(Object? value) {
  if (value is Uint8List) {
    return value;
  }
  if (value is List<int>) {
    return Uint8List.fromList(value);
  }
  if (value is String && value.isNotEmpty) {
    return base64Decode(value);
  }
  return Uint8List(0);
}

Map<String, dynamic>? _dynamicMapOrNull(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return null;
}

Map<String, String> _stringMap(Object? value) {
  final map = _dynamicMapOrNull(value);
  if (map == null) {
    return <String, String>{};
  }
  return map.map((key, value) => MapEntry(key, value.toString()));
}

Map<String, double> _doubleMap(Object? value) =>
    _doubleMapOrNull(value) ?? <String, double>{};

Map<String, double>? _doubleMapOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  if (map == null) {
    return null;
  }
  return map.map(
    (key, value) => MapEntry(
      key,
      value is num ? value.toDouble() : double.parse(value.toString()),
    ),
  );
}

List<String> _stringList(Object? value, {List<String> fallback = const []}) =>
    _stringListOrNull(value) ?? List<String>.from(fallback);

List<String>? _stringListOrNull(Object? value) {
  if (value is! Iterable) {
    return null;
  }
  return value.map((entry) => entry.toString()).toList();
}

List<AgentInputContent> _inputContentList(Object? value) =>
    _inputContentListOrNull(value) ?? <AgentInputContent>[];

List<AgentInputContent>? _inputContentListOrNull(Object? value) {
  if (value is! Iterable) {
    return null;
  }
  return value
      .map(
        (entry) =>
            AgentInputContent.fromJson(Map<String, dynamic>.from(entry as Map)),
      )
      .toList();
}

List<T> _objectList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) fromJson,
) {
  if (value is! Iterable) {
    return <T>[];
  }
  return value
      .map((entry) => fromJson(Map<String, dynamic>.from(entry as Map)))
      .toList();
}

List<Map<String, dynamic>>? _mapListOrNull(Object? value) {
  if (value is! Iterable) {
    return null;
  }
  return value.map((entry) => Map<String, dynamic>.from(entry as Map)).toList();
}

Map<String, TurnToolkitConfig>? _toolkitsOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  if (map == null) {
    return null;
  }
  return map.map(
    (key, value) => MapEntry(
      key,
      TurnToolkitConfig.fromJson(Map<String, dynamic>.from(value as Map)),
    ),
  );
}

ToolChoice? _toolChoiceOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : ToolChoice.fromJson(map);
}

AgentAudioFormat _audioFormatOrDefault(Object? value) =>
    _audioFormatOrNull(value) ?? const AgentAudioFormat();

AgentAudioFormat? _audioFormatOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : AgentAudioFormat.fromJson(map);
}

AgentError? _errorOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : AgentError.fromJson(map);
}

AgentRealtimeConnectionInfo? _realtimeConnectionOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : AgentRealtimeConnectionInfo.fromJson(map);
}

AgentGeneratedImage? _generatedImageOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : AgentGeneratedImage.fromJson(map);
}

AgentGeneratedAudio? _generatedAudioOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : AgentGeneratedAudio.fromJson(map);
}

Content? _contentOrNull(Object? value) {
  final map = _dynamicMapOrNull(value);
  return map == null ? null : unpackContent(packMessage(map));
}

Map<String, dynamic> _contentHeader(Content content) {
  return unpackMessage(content.pack()).header;
}
