import 'package:equatable/equatable.dart';

enum AdStatus {
  draft,
  pendingApproval,
  approved,
  rejected,
  active,
  expired,
  paused;

  String get displayName {
    switch (this) {
      case AdStatus.draft:
        return 'Draft';
      case AdStatus.pendingApproval:
        return 'Pending Approval';
      case AdStatus.approved:
        return 'Approved';
      case AdStatus.rejected:
        return 'Rejected';
      case AdStatus.active:
        return 'Active';
      case AdStatus.expired:
        return 'Expired';
      case AdStatus.paused:
        return 'Paused';
    }
  }

  static AdStatus fromString(String value) {
    switch (value) {
      case 'draft':
        return AdStatus.draft;
      case 'pending_approval':
        return AdStatus.pendingApproval;
      case 'approved':
        return AdStatus.approved;
      case 'rejected':
        return AdStatus.rejected;
      case 'active':
        return AdStatus.active;
      case 'expired':
        return AdStatus.expired;
      case 'paused':
        return AdStatus.paused;
      default:
        return AdStatus.draft;
    }
  }

  String toDbString() {
    switch (this) {
      case AdStatus.draft:
        return 'draft';
      case AdStatus.pendingApproval:
        return 'pending_approval';
      case AdStatus.approved:
        return 'approved';
      case AdStatus.rejected:
        return 'rejected';
      case AdStatus.active:
        return 'active';
      case AdStatus.expired:
        return 'expired';
      case AdStatus.paused:
        return 'paused';
    }
  }
}

enum PaymentStatus {
  pending,
  succeeded,
  failed,
  refunded;

  String get displayName {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.succeeded:
        return 'Succeeded';
      case PaymentStatus.failed:
        return 'Failed';
      case PaymentStatus.refunded:
        return 'Refunded';
    }
  }

  static PaymentStatus fromString(String value) {
    switch (value) {
      case 'pending':
        return PaymentStatus.pending;
      case 'succeeded':
        return PaymentStatus.succeeded;
      case 'failed':
        return PaymentStatus.failed;
      case 'refunded':
        return PaymentStatus.refunded;
      default:
        return PaymentStatus.pending;
    }
  }
}

class AdModel extends Equatable {
  final String? id;
  final String creatorId;
  final String title;
  final String? description;
  final String imageUrl;
  final String linkUrl;
  final DateTime startDate;
  final DateTime endDate;
  final String? adSizeId;
  final String? stripePaymentIntentId;
  final String? stripeCustomerId;
  final double amountPaidCents;
  final String currency;
  final PaymentStatus paymentStatus;
  final AdStatus status;
  final String? rejectionReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? approvedAt;
  final String? approvedBy;

  const AdModel({
    this.id,
    required this.creatorId,
    required this.title,
    this.description,
    required this.imageUrl,
    required this.linkUrl,
    required this.startDate,
    required this.endDate,
    this.adSizeId,
    this.stripePaymentIntentId,
    this.stripeCustomerId,
    this.amountPaidCents = 0.0,
    this.currency = 'USD',
    this.paymentStatus = PaymentStatus.pending,
    this.status = AdStatus.draft,
    this.rejectionReason,
    this.createdAt,
    this.updatedAt,
    this.approvedAt,
    this.approvedBy,
  });

  factory AdModel.fromJson(Map<String, dynamic> json) {
    return AdModel(
      id: json['id'] as String?,
      creatorId: json['creator_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      imageUrl: json['image_url'] as String,
      linkUrl: json['link_url'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      adSizeId: json['ad_size_id'] as String?,
      stripePaymentIntentId: json['stripe_payment_intent_id'] as String?,
      stripeCustomerId: json['stripe_customer_id'] as String?,
      amountPaidCents: json['amount_paid_cents'] as double? ?? 0,
      currency: json['currency'] as String? ?? 'USD',
      paymentStatus: PaymentStatus.fromString(json['payment_status'] as String? ?? 'pending'),
      status: AdStatus.fromString(json['status'] as String? ?? 'draft'),
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: json['created_at'] != null ? DateTime.parse(json['created_at'] as String) : null,
      updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at'] as String) : null,
      approvedAt: json['approved_at'] != null ? DateTime.parse(json['approved_at'] as String) : null,
      approvedBy: json['approved_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'creator_id': creatorId,
      'title': title,
      if (description != null) 'description': description,
      'image_url': imageUrl,
      'link_url': linkUrl,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      if (adSizeId != null) 'ad_size_id': adSizeId,
      if (stripePaymentIntentId != null) 'stripe_payment_intent_id': stripePaymentIntentId,
      if (stripeCustomerId != null) 'stripe_customer_id': stripeCustomerId,
      'amount_paid_cents': amountPaidCents,
      'currency': currency,
      'payment_status': paymentStatus.name,
      'status': status.toDbString(),
      if (rejectionReason != null) 'rejection_reason': rejectionReason,
      if (approvedBy != null) 'approved_by': approvedBy,
    };
  }

  AdModel copyWith({
    String? id,
    String? creatorId,
    String? title,
    String? description,
    String? imageUrl,
    String? linkUrl,
    DateTime? startDate,
    DateTime? endDate,
    String? adSizeId,
    String? stripePaymentIntentId,
    String? stripeCustomerId,
    double? amountPaidCents,
    String? currency,
    PaymentStatus? paymentStatus,
    AdStatus? status,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? approvedAt,
    String? approvedBy,
  }) {
    return AdModel(
      id: id ?? this.id,
      creatorId: creatorId ?? this.creatorId,
      title: title ?? this.title,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      linkUrl: linkUrl ?? this.linkUrl,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      adSizeId: adSizeId ?? this.adSizeId,
      stripePaymentIntentId: stripePaymentIntentId ?? this.stripePaymentIntentId,
      stripeCustomerId: stripeCustomerId ?? this.stripeCustomerId,
      amountPaidCents: amountPaidCents ?? this.amountPaidCents,
      currency: currency ?? this.currency,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      approvedAt: approvedAt ?? this.approvedAt,
      approvedBy: approvedBy ?? this.approvedBy,
    );
  }

  @override
  List<Object?> get props => [
        id,
        creatorId,
        title,
        description,
        imageUrl,
        linkUrl,
        startDate,
        endDate,
        adSizeId,
        stripePaymentIntentId,
        stripeCustomerId,
        amountPaidCents,
        currency,
        paymentStatus,
        status,
        rejectionReason,
        createdAt,
        updatedAt,
        approvedAt,
        approvedBy,
      ];
}
