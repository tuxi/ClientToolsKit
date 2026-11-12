# Failure classification report

This report is diagnostic only. No detector, OCR, crop, or schema behavior was changed after the run began.

- Images: 30
- Hard-failed images: 0
- Hard-failure events: 0
- OCR misses: 289
- OCR false positives: 207
- Container misses: 131
- Container false positives: 847
- Repeated-group misses: 17
- Repeated-group false positives: 32

## Classification

| Image | Hard failures | Text FN | Text FP | Bbox@0.5 misses | Container FN | Group FN | Crop unusable | Crop extras |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| settings_general_light | 0 | 6 | 5 | 19 | 11 | 1 | 0 | 0 |
| settings_privacy_dark | 0 | 12 | 3 | 16 | 8 | 1 | 0 | 3 |
| feed_social_light | 0 | 16 | 9 | 29 | 4 | 1 | 0 | 0 |
| feed_news_compact | 0 | 11 | 20 | 9 | 4 | 1 | 0 | 0 |
| editor_document_light | 0 | 16 | 18 | 23 | 4 | 1 | 0 | 0 |
| editor_code_dark | 0 | 10 | 8 | 33 | 3 | 0 | 0 | 0 |
| form_checkout_desktop | 0 | 4 | 8 | 14 | 3 | 0 | 0 | 0 |
| form_profile_mobile | 0 | 0 | 5 | 8 | 2 | 0 | 0 | 0 |
| payment_card_desktop | 0 | 2 | 4 | 15 | 5 | 1 | 0 | 0 |
| payment_confirm_mobile | 0 | 1 | 2 | 5 | 0 | 0 | 1 | 0 |
| dashboard_analytics_light | 0 | 5 | 2 | 35 | 3 | 1 | 0 | 0 |
| dashboard_ops_dark | 0 | 29 | 2 | 18 | 7 | 1 | 0 | 0 |
| sheet_delete_modal | 0 | 23 | 4 | 3 | 3 | 0 | 0 | 0 |
| sheet_filters_mobile | 0 | 4 | 0 | 16 | 1 | 0 | 0 | 0 |
| list_orders_desktop | 0 | 3 | 6 | 29 | 9 | 1 | 0 | 0 |
| list_notifications_mobile | 0 | 4 | 2 | 10 | 6 | 1 | 1 | 0 |
| search_results_desktop | 0 | 11 | 7 | 13 | 8 | 1 | 0 | 0 |
| search_empty_desktop | 0 | 6 | 5 | 17 | 5 | 0 | 0 | 0 |
| split_mail_desktop | 0 | 13 | 13 | 25 | 4 | 1 | 0 | 0 |
| split_settings_wide | 0 | 8 | 9 | 23 | 6 | 1 | 0 | 0 |
| landscape_media | 0 | 8 | 7 | 10 | 4 | 1 | 0 | 0 |
| landscape_table_finance | 0 | 6 | 11 | 50 | 2 | 1 | 0 | 0 |
| small_text_legal | 0 | 10 | 15 | 18 | 9 | 0 | 0 | 0 |
| low_contrast_form | 0 | 7 | 9 | 10 | 3 | 0 | 0 | 0 |
| repeated_toolbar_calendar | 0 | 13 | 2 | 28 | 5 | 0 | 0 | 0 |
| scroll_feed_mobile | 0 | 7 | 6 | 7 | 1 | 0 | 0 | 0 |
| jpeg_feed_photo | 0 | 15 | 8 | 27 | 4 | 1 | 0 | 3 |
| jpeg_table_finance | 0 | 7 | 11 | 49 | 3 | 1 | 0 | 1 |
| modal_payment_mobile | 0 | 3 | 0 | 3 | 1 | 0 | 0 | 0 |
| search_command_dark | 0 | 29 | 6 | 1 | 3 | 0 | 0 | 0 |

## Hard failures

No hard failures observed.
## Representative misses

- **settings_general_light**: OCR misses: 'C'; 'Filter'; 'Workspace preferences'; 'General'; 'Notifications' · OCR FP: 'Q Projects, people, files'; 'General Workspace preferences'; 'Y Filter'; '>'; 'Q Notifications'
- **settings_privacy_dark**: OCR misses: 'C'; 'Privacy & access'; 'Privacy & access'; 'Low'; '3' · OCR FP: 'Q Projects, people, files'; 'Privac'; '«acces' · Crop nondeterminism: 3 group(s), 3 stale file(s)
- **feed_social_light**: OCR misses: 'C'; 'Design Systems'; '2m'; 'Data science'; 'Settings' · OCR FP: 'Projects, people, files'; 'Design Systems 2m'; 'Data sclence'; '-9: Settings'; 'Like • 128 Comment Share'
- **feed_news_compact**: OCR misses: 'C'; 'Global desks remain focused on supply guidance and demand visibility into next quarter.'; 'A transit network rebuild inches toward its first passenger milestone'; 'Engineers completed overnight tests on the eastern corridor earlier this week.'; 'The next phase of the AI platform race is about distribution' · OCR FP: 'Q Projects, people, files'; '■'; 'a'; 'Global desks remain focused on supply guidance and demand visibility'; 'into next quarter.'
- **editor_document_light**: OCR misses: 'Updates'; 'C'; 'Undo'; 'Redo'; 'Heading' · OCR FP: 'Q Projects, people, files'; 'Q Updates'; 'V Undo'; 'v Redo'; 'v Heading'
- **editor_code_dark**: OCR misses: 'Updates'; 'C'; 'Code'; 'Settings'; 'throw EvidenceError.emptySource' · OCR FP: 'Q Projects, people, files'; '4 Updates'; 'UlEvidenceBenchmarkRunner'; '-o- Settings'; 'Debug'
- **form_checkout_desktop**: OCR misses: 'C'; 'Notifications'; '7'; 'AM' · OCR FP: 'Q Projects, people, files'; 'alex.morgan@example.com'; 'Alex Morgan'; 'Northstar Studio'; 'US-4821-9902'
- **form_profile_mobile**: OCR FP: 'Alex'; 'Morgan'; 'alex@cloudbase.dev'; 'Product designer'; 'く'
- **payment_card_desktop**: OCR misses: 'Notifications'; '7' · OCR FP: 'Q Projects, people, files'; '日'; '••••'; '4 Notifications'
- **payment_confirm_mobile**: OCR misses: 'Your card will be charged today. You can cancel or change seats at any time.' · OCR FP: 'Your card will be charged today. You can cancel or change seats at any'; 'time.'
- **dashboard_analytics_light**: OCR misses: 'C'; 'Oct 26'; 'Nov 2'; 'Notifications'; '7' · OCR FP: 'Q Projects, people, files'; '4 Notifications'
- **dashboard_ops_dark**: OCR misses: 'Operations'; 'Core services'; 'Traffic by region'; 'Gateway'; 'US West' · OCR FP: 'Q Projects, people, files'; 'AMI'
- **sheet_delete_modal**: OCR misses: 'Updates'; 'New'; 'Cloudbase / Workspace'; 'C'; 'Cloudbase' · OCR FP: 'This action cannot be undone. 14 files, 3 integrations, and all'; 'activity history will be permanently removed.'; 'Type ATLAS MIGRATION to confirm'; 'Project name'
- **sheet_filters_mobile**: OCR misses: 'Cancel'; 'Reset'; 'Search'; 'Design systems'
- **list_orders_desktop**: OCR misses: 'Filter'; 'Notifications'; '7' · OCR FP: 'Q Projects, people, files'; 'Y Filter'; 'a'; 'Search orders'; '...'
- **list_notifications_mobile**: OCR misses: '2m'; '18m'; '1h'; '3h' · OCR FP: '2m0'; '18m0'
- **search_results_desktop**: OCR misses: 'C'; 'Filters'; 'All'; 'People'; 'Messages' · OCR FP: 'Q Projects, people, files'; 'a'; 'V Filters'; 'People Messages'; 'Add from:alex to filter by author.'
- **search_empty_desktop**: OCR misses: 'C'; 'quarterly retrospective.pdf'; 'Explore'; 'All'; 'Notifications' · OCR FP: 'Q Projects, people, files'; 'Q quarterly retrospective.pdf'; 'Q Explore'; 'a'; '4 Notifications'
- **split_mail_desktop**: OCR misses: '09:42'; '7'; 'The updated bounds look correct on both mobile and desktop.'; 'MC'; '3' · OCR FP: 'Q Projects, people, files'; 'Search mail'; 'The updated bounds look correct on both mobile and desk...'; 'I revlewed the coverage matrix. The low-contrast cases ar...'; 'The updated bounds look correct on both mobile and desktop. I checked the navigation crop, the repeated'
- **split_settings_wide**: OCR misses: 'Updates'; 'Home'; 'Admins can manage billing and security. Members can create projects and invite guests.'; 'OP'; '9 members' · OCR FP: 'Q Projects, people, files'; '4 Updates'; 'A Home'; 'Admins can manage billing and security.'; 'Members can create projects and invite guests.'
- **landscape_media**: OCR misses: 'Updates'; 'Sort'; 'Atlas field recordings'; '14 clips · 2.6 GB'; 'Explore' · OCR FP: 'Q Projects, people, files'; '4 Updates'; 'Atlas field recordings 14 clips • 2.6 GB'; 'Y Sort'; 'Q Explore'
- **landscape_table_finance**: OCR misses: 'Updates'; 'Home'; 'Explore'; 'Notifications'; '7' · OCR FP: 'Q Projects, people, files'; '4 Updates'; 'A Home'; 'Q Explore'; 'a'
- **small_text_legal**: OCR misses: 'C'; 'Last updated November 1, 2026 · Effective immediately for new evaluations'; 'This document contains intentionally small body text to exercise OCR under realistic dense-reading conditions.'; 'These terms govern access to the Cloudbase evaluation workspace and any related documentation, sample data, or benchmark artifacts made available to the customer. By accessing the workspace, the customer accepts these terms on behalf of the organization identified in the order form.'; 'Cloudbase grants a limited, non-exclusive, non-transferable license to use the evaluation workspace solely for internal testing, quality assessment, and procurement review during the evaluation period. The customer may not redistribute, sublicense, or use the workspace to provide a competing service.' · OCR FP: 'Q Projects, people, files'; 'Inis docume'; 'cise OCR under realistic dense-reading conditions.'; 'These terms govern access to the Cloudbase evaluation workspace and any related documentation, sample data, or benchmark artifacts made available to the customer.'; 'By accessing the workspace, the customer accepts these terms on behalf of the organization identified in the order form.'
- **low_contrast_form**: OCR misses: 'Updates'; 'C'; 'Home'; 'You can update these details at any time in Security settings.'; 'Notifications' · OCR FP: 'Q Projects, people, files'; '4 Updates'; 'A Home'; 'alex.morgan@example.com'; '+1 415 555 0148'
- **repeated_toolbar_calendar**: OCR misses: '1'; '2'; '3'; '4'; '6' · OCR FP: 'Q Projects, people, files'; 'AMI'
- **scroll_feed_mobile**: OCR misses: 'Your story'; 'Maya'; 'Jon'; 'Theo'; 'The quiet navigation experiment is holding up across all three accessibility profiles.' · OCR FP: '口'; 'The quiet navigation experiment is holding up across all three'; 'accessibility profiles.'; 'THI'; 'Three charts, one question: where do evidence reviews lose the most'
- **jpeg_feed_photo**: OCR misses: 'C'; 'Design Systems'; '2m'; 'Research'; '18m' · OCR FP: 'Projects, people, files'; 'Design Systems 2m'; 'Comment Share'; 'Research 18m'; '#QuietInterfaces 1.8k posts' · Crop nondeterminism: 3 group(s), 3 stale file(s)
- **jpeg_table_finance**: OCR misses: 'Updates'; 'C'; 'Home'; 'Explore'; 'Notifications' · OCR FP: 'Q Projects, people, files'; 'Q Updates'; 'A Home'; 'Q Explore'; 'Search accounts' · Crop nondeterminism: 1 group(s), 1 stale file(s)
- **modal_payment_mobile**: OCR misses: 'Cancel'; 'Checkout'; 'Cloudbase Pro · Monthly'
- **search_command_dark**: OCR misses: 'Updates'; 'New'; 'Cloudbase / Workspace'; 'C'; 'Cloudbase' · OCR FP: 'A Pote coate'; 'Q Search evidence'; 'Q New project'; 'Q Invite teammate'; 'Q View benchmark report'
