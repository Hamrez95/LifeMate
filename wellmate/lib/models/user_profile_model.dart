class UserProfileModel {
  final String id;
  final String fullName; // نام و نام خانوادگی
  final String email; // ایمیل کاربر
  final String avatarUrl; // لینک تصویر پروفایل
  final bool isPremium; // آیا کاربر اشتراک ویژه دارد؟
  final String joinDate; // تاریخ عضویت
  final String mobileNumber; // تاریخ عضویت

  UserProfileModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.avatarUrl,
    this.isPremium = false,
    required this.joinDate,
    required this.mobileNumber,
  });

  // پارس کردن JSON بک‌اند
  factory UserProfileModel.fromJson(Map<String, dynamic> json) {
    return UserProfileModel(
      id: json['id']?.toString() ?? '',
      fullName: json['full_name'] ?? 'کاربر مهمان',
      email: json['email'] ?? '',
      avatarUrl: json['avatar_url'] ?? '',
      isPremium: json['is_premium'] ?? false,
      joinDate: json['join_date'] ?? '',
      mobileNumber: json['mobile_number'] ?? '',
    );
  }

  // تبدیل به JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'full_name': fullName,
      'email': email,
      'avatar_url': avatarUrl,
      'is_premium': isPremium,
      'join_date': joinDate,
      'mobile_number': mobileNumber,
    };
  }
}
