CREATE TABLE public.user_fcm_tokens (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  fcm_token text NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT user_fcm_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT user_fcm_tokens_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  CONSTRAINT user_fcm_tokens_unique_user_token UNIQUE (user_id, fcm_token)
);

-- Create an index for faster lookups
CREATE INDEX idx_user_fcm_tokens_user_id ON public.user_fcm_tokens(user_id);

-- Enable RLS (Row Level Security) if you're using it
ALTER TABLE public.user_fcm_tokens ENABLE ROW LEVEL SECURITY;

-- Add policies for RLS (adjust based on your security requirements)
CREATE POLICY "Users can manage their own FCM tokens" 
  ON public.user_fcm_tokens 
  FOR ALL 
  USING (auth.uid() = user_id);
