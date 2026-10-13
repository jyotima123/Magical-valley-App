import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mvc_app/app_theme.dart';
import 'package:mvc_app/modules/cars/vehicle_inquiry_conversation.dart';
import 'package:mvc_app/modules/chat/models/direct_message_item.dart';
import 'package:mvc_app/modules/chat/widgets/image_converter_service.dart';
import 'package:mvc_app/modules/market/market_category.dart';
import 'package:mvc_app/modules/market/market_item.dart';
import 'package:mvc_app/services/api/supabase_api_service.dart';
import 'package:mvc_app/services/api_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VehicleInquiryChatScreen extends StatefulWidget {
  final VehicleInquiryConversation conversation;
  const VehicleInquiryChatScreen({super.key, required this.conversation});

  /// ID of the inquiry conversation currently on screen, if any.
  /// Used by the global FCM banner to avoid notifying about the open chat.
  static String? currentOpenConversationId;

  @override
  State<VehicleInquiryChatScreen> createState() =>
      _VehicleInquiryChatScreenState();
}

class _VehicleInquiryChatScreenState extends State<VehicleInquiryChatScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  List<DirectMessageItem> _messages = [];
  StreamSubscription<List<DirectMessageItem>>? _sub;
  final Set<String> _animatedIds = {};
  String? _currentUserId;
  bool _sendingImage = false;

  VehicleInquiryConversation get conv => widget.conversation;

  @override
  void initState() {
    super.initState();
    VehicleInquiryChatScreen.currentOpenConversationId = conv.id;
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadMessages();
  }

  @override
  void dispose() {
    if (VehicleInquiryChatScreen.currentOpenConversationId == conv.id) {
      VehicleInquiryChatScreen.currentOpenConversationId = null;
    }
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _sub?.cancel();
    super.dispose();
  }

  String get _otherName => conv.counterpartyName(_currentUserId);

  Future<void> _loadMessages() async {
    final api = context.read<ApiRepository>();
    final result =
        await api.getVehicleInquiryMessages(conv.id, limit: 50);

    if (result.isSuccess) {
      final initial = (result.data ?? []).reversed.toList();
      setState(() {
        _messages = initial;
        _animatedIds.addAll(initial.map((m) => m.id));
      });
      _scrollToBottom();

      if (_currentUserId != null) {
        api.markVehicleInquiryMessagesAsRead(conv.id, _currentUserId!);
      }

      _sub?.cancel();
      _sub = api.streamVehicleInquiryMessages(conv.id).listen((msgs) {
        if (!mounted) return;
        final prev = _messages.map((m) => m.id).toSet();
        final updated = msgs.reversed.toList();
        final newIds =
            updated.where((m) => !prev.contains(m.id)).map((m) => m.id).toSet();

        setState(() {
          _messages = updated;
          _animatedIds.addAll(newIds);
        });

        if (newIds.isNotEmpty) {
          _scrollToBottom();
          if (_currentUserId != null) {
            api.markVehicleInquiryMessagesAsRead(conv.id, _currentUserId!);
          }
        }
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();

    final api = context.read<ApiRepository>();
    final result = await api.sendVehicleInquiryMessage(conv.id, text);

    if (!result.isSuccess && mounted) {
      _msgCtrl.text = text;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.error ?? 'Failed to send'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _pickAndSendImages() async {
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty || !mounted) return;

    setState(() => _sendingImage = true);
    final api = context.read<ApiRepository>();

    try {
      for (final xFile in picked) {
        Uint8List bytes = await xFile.readAsBytes();

        if (ImageConverterService.isHeicFormat(bytes)) {
          final converted =
              await ImageConverterService.convertHeicToPng(bytes);
          if (converted != null) bytes = converted;
        }

        final upload = await SupabaseApiService.instance.uploadGenericFile(
          fileBytes: bytes,
          fileName:
              'vehicle_inquiry_${DateTime.now().millisecondsSinceEpoch}.png',
          userId: _currentUserId,
        );

        if (!upload.isSuccess || upload.data == null) {
          throw Exception(upload.error ?? 'Failed to upload image');
        }

        final result = await api.sendVehicleInquiryMessage(
          conv.id,
          '📷 Photo',
          messageType: 'image',
          fileUrl: upload.data as String,
        );
        if (!result.isSuccess) {
          throw Exception(result.error ?? 'Failed to send image');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: AppTheme.headerBackground,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _otherName,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.black,
              ),
            ),
            Text(
              conv.listingTitle,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          _ListingBanner(conv: conv),
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final msg = _messages[i];
                final isMe = msg.senderId == _currentUserId;
                return _MessageBubble(message: msg, isMe: isMe);
              },
            ),
          ),
          _buildInput(),
        ],
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        8,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          if (_sendingImage)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accentPrimary,
                ),
              ),
            )
          else
            IconButton(
              onPressed: _pickAndSendImages,
              icon: const Icon(Icons.add_photo_alternate_outlined),
              color: AppTheme.accentPrimary,
              iconSize: 24,
              tooltip: 'Send photos',
              padding: EdgeInsets.zero,
              constraints:
                  const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
          Expanded(
            child: TextField(
              controller: _msgCtrl,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontFamily: 'Poppins', fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: Colors.grey.shade400,
                ),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _send,
            icon: const Icon(Icons.send_rounded),
            color: AppTheme.accentPrimary,
            iconSize: 24,
          ),
        ],
      ),
    );
  }
}

/// What the conversation is about — a vehicle or a Market item.
class _ListingBanner extends StatelessWidget {
  final VehicleInquiryConversation conv;
  const _ListingBanner({required this.conv});

  @override
  Widget build(BuildContext context) {
    final imageUrl = conv.listingImageUrl;
    final price = conv.listingPrice;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: imageUrl != null
                ? Image.network(
                    imageUrl,
                    width: 56,
                    height: 42,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conv.listingTitle,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (price != null)
                  Text(
                    _formatPrice(price),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentPrimary,
                    ),
                  ),
              ],
            ),
          ),
          // The thread outlives the sale (buyer and seller may still be
          // arranging pickup), so say so rather than hide it.
          if (conv.listingIsSold)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Sold',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Vehicles keep their whole-dollar display; an item can be listed to the
  /// cent, or for free.
  String _formatPrice(double price) {
    if (!conv.isMarketItem) {
      return '\$${price.round().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
    }
    return price == 0 ? 'Free' : MarketItem.formatPrice(price);
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 42,
      color: const Color(0xFFF0F0F0),
      child: Icon(
        conv.isMarketItem
            ? MarketCategory.iconFor(conv.listingCategory)
            : Icons.directions_car_outlined,
        size: 24,
        color: Colors.grey.shade300,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final DirectMessageItem message;
  final bool isMe;
  const _MessageBubble({required this.message, required this.isMe});

  bool get _isImage =>
      message.messageType == 'image' && message.fileUrl != null;

  void _openFullscreenImage(BuildContext context) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        child: InteractiveViewer(
          child: Center(
            child: Image.network(
              message.fileUrl!,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullscreenImage(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          message.fileUrl!,
          width: 200,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              width: 200,
              height: 150,
              color: Colors.black.withValues(alpha: 0.05),
              child: const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          },
          errorBuilder: (_, __, ___) => Container(
            width: 200,
            height: 150,
            color: Colors.black.withValues(alpha: 0.05),
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.grey.shade400,
              size: 40,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: _isImage
            ? const EdgeInsets.all(4)
            : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.accentPrimary : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          boxShadow: [
            if (!isMe)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isImage)
              _buildImageContent(context)
            else
              Text(
                message.content,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  color: isMe ? Colors.white : AppTheme.black,
                  height: 1.4,
                ),
              ),
            const SizedBox(height: 2),
            Padding(
              padding: _isImage
                  ? const EdgeInsets.only(right: 6, bottom: 2)
                  : EdgeInsets.zero,
              child: Text(
                _formatTime(message.createdAt),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: isMe ? Colors.white70 : Colors.grey.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $ampm';
  }
}
