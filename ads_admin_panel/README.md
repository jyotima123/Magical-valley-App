# Ads Admin Panel

A Flutter web application for managing advertisements in the MVC App. This admin panel allows superadmins and advertisers to create, customize, and publish ads.

## Features

- **Authentication**: Secure login using Supabase authentication
- **Ad Management**: Create, edit, and delete ads
- **Image Upload**: Upload ad images to Supabase storage
- **Scheduling**: Set start and end dates for ad campaigns
- **Payment Tracking**: Track Stripe payment information
- **Role-based Access**:
  - **Advertisers**: Can manage their own ads
  - **Superadmins**: Can view and approve/reject all ads

## Prerequisites

- Flutter SDK: ^3.9.0-28.0.dev (same as main app)
- Supabase project with configured authentication and storage
- Access to the `.env_qa` and `.env_prod` files with Supabase credentials

## Setup

1. **Install dependencies**:
   ```bash
   flutter pub get
   ```

2. **Environment Configuration**:
   - The `.env_qa` and `.env_prod` files should already be copied from the main project
   - Verify they contain:
     ```
     SUPABASE_URL=your_supabase_url
     SUPABASE_ANON_KEY=your_anon_key
     ```

3. **Database Setup**:
   - Run the migration files in order:
     - `migrations/047_ads_system.sql` - Creates the ads table and functions
     - `migrations/048_ads_storage_bucket.sql` - Sets up storage bucket policies

   - **IMPORTANT**: Create the 'ads' storage bucket via Supabase Dashboard:
     1. Go to Storage section
     2. Click "Create Bucket"
     3. Name: "ads"
     4. Public: true (checked)
     5. File size limit: 5MB
     6. Allowed MIME types: image/jpeg, image/png, image/webp, image/gif

4. **User Roles**:
   - Update user roles in the database to grant access:
     ```sql
     -- Make a user an advertiser
     UPDATE user_profiles
     SET role = 'advertiser'
     WHERE email = 'user@example.com';

     -- Make a user a superadmin
     UPDATE user_profiles
     SET role = 'superadmin'
     WHERE email = 'admin@example.com';
     ```

## Running the App

### Development (QA environment)
```bash
flutter run -d chrome
```

### Production Build
```bash
flutter build web --release
```

The built files will be in `build/web/` and can be deployed to any static hosting service.

## Usage

### For Advertisers

1. **Login**: Sign in with your advertiser account
2. **Create Ad**:
   - Click the "Create Ad" floating action button
   - Fill in ad details (title, description, link URL)
   - Select an image for the ad
   - Set start and end dates
   - Enter payment amount
   - Click "Create Ad"
3. **Edit Ad**: Click "Edit" on draft or rejected ads
4. **Delete Ad**: Click "Delete" on draft ads only

### For Superadmins

1. **Login**: Sign in with your superadmin account
2. **View All Ads**: See all ads from all advertisers
3. **Approve Ads**: Click "Approve" on pending ads
4. **Reject Ads**: Click "Reject" and provide a reason
5. **All advertiser actions**: Can also create and manage ads

## Ad Status Flow

1. **Draft**: Initial state when created
2. **Pending Approval**: After advertiser submits for review
3. **Approved**: Superadmin approved the ad
4. **Active**: Ad is currently running (automatic based on dates)
5. **Expired**: Ad campaign has ended
6. **Rejected**: Superadmin rejected the ad
7. **Paused**: Ad is temporarily paused

## Tech Stack

- **Frontend**: Flutter Web
- **Backend**: Supabase (PostgreSQL)
- **Authentication**: Supabase Auth
- **Storage**: Supabase Storage
- **State Management**: flutter_bloc
- **File Upload**: file_picker
- **Image Caching**: cached_network_image

## Project Structure

```
lib/
├── config/
│   └── supabase_config.dart      # Supabase initialization
├── models/
│   └── ad_model.dart              # Ad data model
├── screens/
│   ├── auth_screen.dart           # Login screen
│   ├── home_screen.dart           # Main ads list
│   └── ad_form_screen.dart        # Create/edit ad form
├── services/
│   └── ad_service.dart            # API service for ads
└── main.dart                      # App entry point
```

## Database Schema

### ads table
- `id`: UUID (primary key)
- `creator_id`: UUID (references user_profiles)
- `title`: VARCHAR(255)
- `description`: TEXT
- `image_url`: TEXT
- `link_url`: TEXT
- `start_date`: TIMESTAMP
- `end_date`: TIMESTAMP
- `stripe_payment_intent_id`: VARCHAR(255)
- `stripe_customer_id`: VARCHAR(255)
- `amount_paid_cents`: INTEGER
- `currency`: VARCHAR(3)
- `payment_status`: VARCHAR(50)
- `status`: VARCHAR(50)
- `rejection_reason`: TEXT
- `created_at`: TIMESTAMP
- `updated_at`: TIMESTAMP
- `approved_at`: TIMESTAMP
- `approved_by`: UUID

## Security

- Row Level Security (RLS) policies ensure users can only access their own ads
- Superadmins can access all ads
- Storage policies restrict image uploads to advertisers and superadmins
- All API calls are authenticated through Supabase

## Future Enhancements

- [ ] Stripe payment integration
- [ ] Ad analytics and click tracking
- [ ] Ad preview before publishing
- [ ] Bulk ad upload
- [ ] Ad templates
- [ ] Campaign management
- [ ] Budget tracking
- [ ] A/B testing for ads

## Troubleshooting

### "Failed to upload image"
- Ensure the 'ads' storage bucket is created in Supabase
- Check storage RLS policies are configured correctly
- Verify user has 'advertiser' or 'superadmin' role

### "Failed to fetch ads"
- Check database migrations are applied
- Verify RLS policies are configured
- Ensure user is authenticated

### "User not authenticated"
- Clear browser cache
- Check .env file has correct Supabase credentials
- Verify user exists in user_profiles table

## Support

For issues or questions, please contact the development team or create an issue in the project repository.
