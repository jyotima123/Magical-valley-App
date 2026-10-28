> -- Promote user to admin for specific organization
> SELECT promote_user_to_admin('alisson+4@fullpond.co', 'organization-uuid-here');
> 
> -- Auto-confirm email
> SELECT auto_confirm_email('alisson+4@fullpond.co');
> 
> -- Promote using organization name (convenience)
> SELECT promote_user_to_admin_by_org_name('alisson+4@fullpond.co', 'Automotive Test');
>
