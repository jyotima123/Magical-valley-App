-- Supabase Database Creation Script
-- Business Rules Implementation for Company Broadcasting Platform

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. Categories Table
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Insert default categories
INSERT INTO categories (name, description) VALUES
    ('Arts and Performance', 'Theatres, music venues, and performance arts companies'),
    ('Automotive', 'Car manufacturers, dealerships, and automotive services providers'),
    ('Beauty and Personal Care', 'Cosmetics companies, beauty salons, and personal care product manufacturers'),
    ('Cultural and Community', 'Museums, galleries, community centers, and cultural organizations'),
    ('Education', 'Schools, universities, educational publishers, and EdTech companies'),
    ('Entertainment and Leisure', 'Movie theaters, theme parks, and sports activity providers'),
    ('Health and Wellness', 'Hospitals, healthcare services, gyms, and wellness product manufacturers'),
    ('Financial', 'Banks, investment firms, fintech companies, and financial services providers'),
    ('Hobby and Interest', 'Gaming companies, hobby stores, and interest-based businesses'),
    ('Home Services', 'House cleaning services, handyman services, and home maintenance companies'),
    ('Hospitality', 'Hotels, restaurants, bed-and-breakfasts, and other hospitality services'),
    ('Non-profit and Volunteer', 'Charities, non-profit organizations, and volunteer-based groups'),
    ('Professional Services', 'Law firms, accounting services, consulting companies, and other professional services'),
    ('Food', 'Food service providers, restaurants, and food delivery companies'),
    ('Retail and Grocery Stores', 'Department stores, retail shops, supermarkets, and grocery stores');

-- 2. Organizations Table
CREATE TABLE organizations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    logo_url TEXT,
    follower_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 3. Organization Categories Junction Table (Many-to-Many)
CREATE TABLE organization_categories (
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    category_id UUID REFERENCES categories(id) ON DELETE CASCADE,
    PRIMARY KEY (organization_id, category_id)
);

-- 4. User Profiles Table
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    username VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    profile_picture_url TEXT,
    role VARCHAR(20) DEFAULT 'regular' CHECK (role IN ('regular', 'admin', 'superadmin')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT username_format CHECK (
        username ~ '^[a-zA-Z0-9_@.+]{3,24}$' OR
        username ~ '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    )
);

-- 5. Admin Organization Assignments Table
CREATE TABLE admin_organizations (
    user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    assigned_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (user_id, organization_id)
);

-- 6. Request Queue Table
CREATE TABLE request_queue (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
    request_type VARCHAR(50) NOT NULL CHECK (request_type IN ('create_organization', 'assign_organization', 'remove_organization')),
    destination_id UUID, -- This could be organization_id or other relevant ID
    request_data JSONB, -- Additional request information
    status VARCHAR(20) DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    reviewed_by UUID REFERENCES user_profiles(id),
    reviewed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 7. Posts Table
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    created_by UUID REFERENCES user_profiles(id),
    title VARCHAR(255),
    content TEXT,
    post_type VARCHAR(20) NOT NULL CHECK (post_type IN ('text', 'image', 'pdf')),
    file_url TEXT,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'archived', 'fixated')),
    view_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    CONSTRAINT file_required_for_media CHECK (
        (post_type = 'text') OR 
        (post_type IN ('image', 'pdf') AND file_url IS NOT NULL)
    )
);

-- 8. Following Relationships Table
CREATE TABLE user_follows (
    user_id UUID REFERENCES user_profiles(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
    followed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    PRIMARY KEY (user_id, organization_id)
);

-- 9. Post Views Table
CREATE TABLE post_views (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL, -- SET NULL for archival
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    viewed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX idx_organizations_name ON organizations(name);
CREATE INDEX idx_user_profiles_email ON user_profiles(email);
CREATE INDEX idx_user_profiles_username ON user_profiles(username);
CREATE INDEX idx_user_profiles_role ON user_profiles(role);
CREATE INDEX idx_posts_organization ON posts(organization_id);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_user_follows_user ON user_follows(user_id);
CREATE INDEX idx_user_follows_org ON user_follows(organization_id);
CREATE INDEX idx_post_views_user_post ON post_views(user_id, post_id);
CREATE INDEX idx_post_views_post ON post_views(post_id);
CREATE INDEX idx_post_views_viewed_at ON post_views(viewed_at);
CREATE INDEX idx_request_queue_status ON request_queue(status);

-- Triggers and Functions

-- Function to update follower count
CREATE OR REPLACE FUNCTION update_follower_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE organizations 
        SET follower_count = follower_count + 1,
            updated_at = NOW()
        WHERE id = NEW.organization_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE organizations 
        SET follower_count = follower_count - 1,
            updated_at = NOW()
        WHERE id = OLD.organization_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

-- Trigger for follower count updates
CREATE TRIGGER trigger_update_follower_count
    AFTER INSERT OR DELETE ON user_follows
    FOR EACH ROW EXECUTE FUNCTION update_follower_count();

-- Function to update post view count
CREATE OR REPLACE FUNCTION update_post_view_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE posts 
    SET view_count = view_count + 1,
        updated_at = NOW()
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for post view count updates
CREATE TRIGGER trigger_update_post_view_count
    AFTER INSERT ON post_views
    FOR EACH ROW EXECUTE FUNCTION update_post_view_count();

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at timestamps
CREATE TRIGGER trigger_categories_updated_at BEFORE UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_organizations_updated_at BEFORE UPDATE ON organizations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_user_profiles_updated_at BEFORE UPDATE ON user_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_posts_updated_at BEFORE UPDATE ON posts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER trigger_request_queue_updated_at BEFORE UPDATE ON request_queue FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to ensure admin has organization assignment
CREATE OR REPLACE FUNCTION check_admin_organization_assignment()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.role = 'admin' THEN
        -- Check if admin has at least one organization assignment
        IF NOT EXISTS (SELECT 1 FROM admin_organizations WHERE user_id = NEW.id) THEN
            RAISE EXCEPTION 'Admin users must be assigned to at least one organization';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to check admin organization assignment (disabled initially for setup)
-- CREATE TRIGGER trigger_check_admin_organization_assignment
--     AFTER UPDATE ON user_profiles
--     FOR EACH ROW EXECUTE FUNCTION check_admin_organization_assignment();

-- Function to ensure organization has at least one category
CREATE OR REPLACE FUNCTION check_organization_category()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        -- Check if organization would have no categories after delete
        IF NOT EXISTS (
            SELECT 1 FROM organization_categories 
            WHERE organization_id = OLD.organization_id 
            AND category_id != OLD.category_id
        ) THEN
            RAISE EXCEPTION 'Organization must belong to at least one category';
        END IF;
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to ensure organization always has at least one category
CREATE TRIGGER trigger_check_organization_category
    BEFORE DELETE ON organization_categories
    FOR EACH ROW EXECUTE FUNCTION check_organization_category();

-- Function to prevent regular users from being assigned to organizations
CREATE OR REPLACE FUNCTION check_user_role_for_organization()
RETURNS TRIGGER AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM user_profiles 
        WHERE id = NEW.user_id 
        AND role = 'regular'
    ) THEN
        RAISE EXCEPTION 'Regular users cannot be assigned to organizations';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to check user role for organization assignment
CREATE TRIGGER trigger_check_user_role_for_organization
    BEFORE INSERT ON admin_organizations
    FOR EACH ROW EXECUTE FUNCTION check_user_role_for_organization();

-- Row Level Security (RLS) Policies

-- Enable RLS on all tables
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE admin_organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE request_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;

-- Categories: Read-only for most users, full access for superadmins
CREATE POLICY "Categories are viewable by everyone" ON categories FOR SELECT USING (true);
CREATE POLICY "Only superadmins can modify categories" ON categories FOR ALL USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'superadmin')
);

-- Organizations: Viewable by all authenticated users
CREATE POLICY "Organizations are viewable by authenticated users" ON organizations FOR SELECT USING (auth.role() = 'authenticated');
CREATE POLICY "Superadmins can manage all organizations" ON organizations FOR ALL USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'superadmin')
);

-- User profiles: Users can see their own profile
CREATE POLICY "Users can view their own profile" ON user_profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Superadmins can view all profiles" ON user_profiles FOR SELECT USING (
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'superadmin')
);

-- Posts: Users can see active posts from organizations they follow
CREATE POLICY "Users can view posts from followed organizations" ON posts FOR SELECT USING (
    status = 'active' AND (
        EXISTS (SELECT 1 FROM user_follows WHERE user_id = auth.uid() AND organization_id = posts.organization_id) OR
        EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role IN ('admin', 'superadmin'))
    )
);

-- Admins can manage posts for their organizations
CREATE POLICY "Admins can manage their organization posts" ON posts FOR ALL USING (
    EXISTS (SELECT 1 FROM admin_organizations ao 
            JOIN user_profiles up ON ao.user_id = up.id 
            WHERE up.id = auth.uid() AND ao.organization_id = posts.organization_id) OR
    EXISTS (SELECT 1 FROM user_profiles WHERE id = auth.uid() AND role = 'superadmin')
);

-- User follows: Users can manage their own follows
CREATE POLICY "Users can manage their own follows" ON user_follows FOR ALL USING (auth.uid() = user_id);

-- Post views: Users can create views for posts they can access
CREATE POLICY "Users can create post views" ON post_views FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Comments for documentation
COMMENT ON TABLE categories IS 'Industry categories for organizing companies';
COMMENT ON TABLE organizations IS 'Companies that broadcast content to followers';
COMMENT ON TABLE user_profiles IS 'User accounts with role-based permissions';
COMMENT ON TABLE admin_organizations IS 'Junction table for admin-organization assignments';
COMMENT ON TABLE request_queue IS 'Queue for organization creation and assignment requests';
COMMENT ON TABLE posts IS 'Content created by organizations for their followers';
COMMENT ON TABLE user_follows IS 'Following relationships between users and organizations';
COMMENT ON TABLE post_views IS 'Tracking user engagement with posts';

-- Create a view for post analytics
CREATE VIEW post_analytics AS
SELECT 
    p.id,
    p.title,
    p.organization_id,
    o.name as organization_name,
    p.post_type,
    p.status,
    p.view_count,
    COUNT(pv.id) as total_views,
    COUNT(DISTINCT pv.user_id) as unique_viewers,
    p.created_at,
    p.updated_at
FROM posts p
LEFT JOIN post_views pv ON p.id = pv.post_id
LEFT JOIN organizations o ON p.organization_id = o.id
GROUP BY p.id, o.name;

-- Create a view for organization statistics  
CREATE VIEW organization_stats AS
SELECT 
    o.id,
    o.name,
    o.follower_count,
    COUNT(p.id) as total_posts,
    COUNT(CASE WHEN p.status = 'active' THEN 1 END) as active_posts,
    COUNT(CASE WHEN p.status = 'fixated' THEN 1 END) as fixated_posts,
    COALESCE(SUM(p.view_count), 0) as total_views
FROM organizations o
LEFT JOIN posts p ON o.id = p.organization_id
GROUP BY o.id, o.name, o.follower_count;
