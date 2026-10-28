import 'package:flutter/material.dart';

class StaticCategories {
  static IconData getCategoryIcon(String? id) {
    // Try to find the category with the matching ID
    final category = categories.firstWhere(
      (category) => category['id'] == id,
      orElse: () => {'icon': Icons.category}, // Default if not found
    );

    // Return the icon from the found category or the default
    return category['icon'] as IconData;
  }

  static IconData getCategoryIconByName(String? name) {
    if (name == null) return Icons.category;

    final category = categories.firstWhere(
      (cat) => (cat['label'] as String).toLowerCase() == name.toLowerCase(),
      orElse: () => {'icon': Icons.category},
    );

    return category['icon'] as IconData;
  }

  static final List<Map<String, dynamic>> categories = [
    {'id': null, 'label': 'All', 'icon': Icons.star},
    {
      'id': 'afca8374-baed-42fd-aa6e-9dfa311c2b7f',
      'label': 'Arts and Performance',
      'icon': Icons.palette,
    },
    {
      'id': '4fc7b758-1099-4248-8b18-c82df76ad0b4',
      'label': 'Automotive',
      'icon': Icons.build,
    },
    {
      'id': '942ae6fb-0e59-458e-8615-285c52ec2809',
      'label': 'Beauty and Personal Care',
      'icon': Icons.face_retouching_natural,
    },
    {
      'id': '50bf2bb5-b841-4670-aead-ba09350f8c8d',
      'label': 'Cultural and Community',
      'icon': Icons.people,
    },
    {
      'id': '1a55000d-2bca-4a14-98b1-2d0301aafec9',
      'label': 'Education',
      'icon': Icons.school,
    },
    {
      'id': 'bee3a0d9-dce8-4c18-9fb1-b7450f15f97f',
      'label': 'Entertainment and Leisure',
      'icon': Icons.sports,
    },
    {
      'id': 'c6bc8da6-cf63-495e-84ed-1be6598a3c11',
      'label': 'Sports',
      'icon': Icons.sports_soccer_rounded,
    },
    {
      'id': 'cdec5d45-b365-453d-ac8d-849ddd3e06a0',
      'label': 'Health and Wellness',
      'icon': Icons.self_improvement,
    },
    {
      'id': '2cde8c6d-c3bb-4d1b-83be-35d678896691',
      'label': 'Financial',
      'icon': Icons.bar_chart,
    },
    {
      'id': 'c3fec5f5-9887-4941-8584-05499adbb591',
      'label': 'Hobby and Interest',
      'icon': Icons.brush,
    },
    {
      'id': '70d5d1a1-560d-4e5d-b617-ed99df715a53',
      'label': 'Home Services',
      'icon': Icons.handyman,
    },
    {
      'id': '48b89662-472f-45fe-b5bc-dda64703d6c7',
      'label': 'Hospitality',
      'icon': Icons.room_service,
    },
    {
      'id': '08993791-4c72-4b15-9761-c1c6c8817b6e',
      'label': 'Non-profit and Volunteer',
      'icon': Icons.volunteer_activism,
    },
    {
      'id': '869fb505-edb0-49cf-bf75-88ca377435f3',
      'label': 'Professional Services',
      'icon': Icons.workspace_premium,
    },
    {
      'id': '5214db34-cdfe-4c7c-a856-0b617e08b7cf',
      'label': 'Food',
      'icon': Icons.restaurant,
    },
    {
      'id': '4cefb200-87da-486d-ac8a-1f9281326a5d',
      'label': 'Retail and Grocery Stores',
      'icon': Icons.shopping_basket,
    },
  ];
}
