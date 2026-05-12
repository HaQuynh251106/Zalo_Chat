import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'api_client.dart';

/// Thin WebRTC client that wires our existing signaling layer
/// (REST `/calls/{id}/signal` + WS event `call.signal`) into a real
/// `RTCPeerConnection` so 1-1 calls actually carry audio/video.
///
/// Concurrency model:
///   - `init()` resolves [ready]. All `handleSignal()` and
///     `startIfCaller()` calls await [ready] internally so they can be
///     invoked freely before init completes — they just queue up.
///   - Inbound signals are serialized via an internal future-chain so
///     SDP/ICE arrive in order even when callers fire them concurrently.
class RtcClient {
  final ApiClient api;
  final String callId;
  final bool isCaller;

  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final _pendingRemoteIce = <RTCIceCandidate>[];
  bool _hasRemoteDesc = false;
  bool _disposed = false;

  final _readyCompleter = Completer<void>();
  Future<void> get ready => _readyCompleter.future;

  Future<void> _signalChain = Future.value();

  final _onRemoteStreamCtl = StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get onRemoteStream => _onRemoteStreamCtl.stream;

  RtcClient({required this.api, required this.callId, required this.isCaller});

  Future<void> init({required bool withVideo}) async {
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();

      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': withVideo
            ? {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              }
            : false,
      });
      localRenderer.srcObject = _localStream;

      _pc = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
      });

      // Set track handler BEFORE adding tracks / remote descriptions so we
      // never miss the first inbound track event.
      _pc!.onTrack = (event) {
        if (kDebugMode) {
          debugPrint('[rtc] onTrack: kind=${event.track.kind} streams=${event.streams.length}');
        }
        if (event.streams.isNotEmpty) {
          remoteRenderer.srcObject = event.streams.first;
          if (!_onRemoteStreamCtl.isClosed) {
            _onRemoteStreamCtl.add(event.streams.first);
          }
        }
      };

      _pc!.onIceCandidate = (cand) {
        if (cand.candidate == null) return;
        _sendSignal('ice', {
          'candidate': cand.candidate,
          'sdpMid': cand.sdpMid,
          'sdpMLineIndex': cand.sdpMLineIndex,
        });
      };

      _pc!.onConnectionState = (s) {
        if (kDebugMode) debugPrint('[rtc] pcState=$s');
      };

      // Attach local tracks BEFORE creating offer/answer so SDP carries them.
      for (final t in _localStream!.getTracks()) {
        await _pc!.addTrack(t, _localStream!);
      }

      if (!_readyCompleter.isCompleted) _readyCompleter.complete();
    } catch (e, st) {
      if (!_readyCompleter.isCompleted) _readyCompleter.completeError(e, st);
      rethrow;
    }
  }

  /// If we are the caller, create + send the SDP offer.
  /// Safe to call before [init] completes; will await [ready].
  Future<void> startIfCaller() async {
    if (!isCaller) return;
    try {
      await ready;
    } catch (_) {
      return;
    }
    if (_disposed || _pc == null) return;
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _pc!.setLocalDescription(offer);
    _sendSignal('offer', {'type': offer.type, 'sdp': offer.sdp});
    if (kDebugMode) debugPrint('[rtc] offer sent (${offer.sdp?.length} chars)');
  }

  /// Handle an inbound `call.signal` WS payload.
  /// payload = { call_id, from, kind, payload }.
  /// Multiple concurrent calls are serialized through a future chain so
  /// SDP must-precede-ICE ordering is preserved.
  Future<void> handleSignal(Map<String, dynamic> ev) {
    final future = _signalChain
        .then((_) => ready)
        .then((_) => _processSignal(ev))
        .catchError((e, st) {
      if (kDebugMode) debugPrint('[rtc] signal err: $e');
    });
    _signalChain = future;
    return future;
  }

  Future<void> _processSignal(Map<String, dynamic> ev) async {
    if (_disposed || _pc == null) return;
    final kind = ev['kind'] as String?;
    final inner = (ev['payload'] as Map?)?.cast<String, dynamic>();
    if (kind == null || inner == null) return;

    switch (kind) {
      case 'offer':
        if (isCaller) return; // ignore self-originated offer echo
        await _pc!.setRemoteDescription(RTCSessionDescription(
            inner['sdp'] as String, inner['type'] as String));
        _hasRemoteDesc = true;
        await _drainPendingIce();
        final answer = await _pc!.createAnswer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': true,
        });
        await _pc!.setLocalDescription(answer);
        _sendSignal('answer', {'type': answer.type, 'sdp': answer.sdp});
        if (kDebugMode) debugPrint('[rtc] answer sent');
        break;
      case 'answer':
        if (!isCaller) return;
        await _pc!.setRemoteDescription(RTCSessionDescription(
            inner['sdp'] as String, inner['type'] as String));
        _hasRemoteDesc = true;
        await _drainPendingIce();
        if (kDebugMode) debugPrint('[rtc] answer applied');
        break;
      case 'ice':
        final cand = RTCIceCandidate(
          inner['candidate'] as String?,
          inner['sdpMid'] as String?,
          inner['sdpMLineIndex'] as int?,
        );
        if (_hasRemoteDesc) {
          await _pc!.addCandidate(cand);
        } else {
          _pendingRemoteIce.add(cand);
        }
        break;
    }
  }

  Future<void> _drainPendingIce() async {
    while (_pendingRemoteIce.isNotEmpty && _pc != null) {
      final c = _pendingRemoteIce.removeAt(0);
      try {
        await _pc!.addCandidate(c);
      } catch (e) {
        if (kDebugMode) debugPrint('[rtc] ice add err: $e');
      }
    }
  }

  void _sendSignal(String kind, Map<String, dynamic> payload) {
    api.post('/calls/$callId/signal', body: {
      'kind': kind,
      'payload': payload,
    }).catchError((e) {
      if (kDebugMode) debugPrint('[rtc] signal POST err: $e');
      return null;
    });
  }

  Future<void> setMic(bool enabled) async {
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  Future<void> setVideo(bool enabled) async {
    for (final t in _localStream?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = enabled;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _onRemoteStreamCtl.close();
    await _pc?.close();
    for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
      await t.stop();
    }
    await _localStream?.dispose();
    await localRenderer.dispose();
    await remoteRenderer.dispose();
  }
}
