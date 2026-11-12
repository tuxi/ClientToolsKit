# v1.1 residual misses and failure classification

Hard failures are contract/integrity failures. Benchmark-definition findings are listed separately.

## Hard failures

No hard failures observed.

## Per-image residual content misses

| Image | Strict leaf FN | Strict bbox@0.5 recall | Full-line misses | Semantic F1 | Vision F1 | Group F1 |
|---|---:|---:|---:|---:|---:|---:|
| settings_general_light | 6 | 45.65% | 3 | 5.13% | 13.95% | 0.00% |
| settings_privacy_dark | 12 | 26.32% | 11 | 18.60% | 39.29% | 0.00% |
| feed_social_light | 16 | 32.84% | 3 | 18.87% | 31.03% | 0.00% |
| feed_news_compact | 11 | 51.22% | 9 | 24.24% | 53.66% | 0.00% |
| editor_document_light | 16 | 17.02% | 5 | 16.67% | 21.05% | 0.00% |
| editor_code_dark | 10 | 18.87% | 8 | 18.18% | 21.62% | 0.00% |
| form_checkout_desktop | 4 | 52.63% | 3 | 12.90% | 25.64% | 0.00% |
| form_profile_mobile | 0 | 42.86% | 0 | 0.00% | 30.77% | 0.00% |
| payment_card_desktop | 2 | 55.26% | 1 | 20.51% | 23.81% | 0.00% |
| payment_confirm_mobile | 1 | 62.50% | 1 | 19.05% | 25.00% | 0.00% |
| dashboard_analytics_light | 5 | 29.82% | 4 | 16.67% | 25.00% | 0.00% |
| dashboard_ops_dark | 29 | 25.40% | 19 | 11.54% | 18.18% | 0.00% |
| sheet_delete_modal | 3 | 0.00% | 2 | 8.00% | 14.29% | 0.00% |
| sheet_filters_mobile | 0 | 15.79% | 0 | 0.00% | 21.28% | 0.00% |
| list_orders_desktop | 3 | 44.83% | 1 | 4.65% | 19.05% | 0.00% |
| list_notifications_mobile | 4 | 41.67% | 4 | 0.00% | 17.14% | 0.00% |
| search_results_desktop | 11 | 46.67% | 5 | 6.25% | 19.05% | 0.00% |
| search_empty_desktop | 6 | 23.33% | 3 | 0.00% | 26.67% | 0.00% |
| split_mail_desktop | 13 | 38.71% | 12 | 12.90% | 32.56% | 0.00% |
| split_settings_wide | 8 | 32.61% | 4 | 23.53% | 36.84% | 0.00% |
| landscape_media | 8 | 47.06% | 2 | 11.76% | 39.13% | 0.00% |
| landscape_table_finance | 6 | 21.13% | 2 | 8.16% | 21.82% | 0.00% |
| small_text_legal | 10 | 22.22% | 9 | 7.69% | 16.67% | 0.00% |
| low_contrast_form | 7 | 29.17% | 4 | 10.00% | 23.08% | 0.00% |
| repeated_toolbar_calendar | 13 | 46.05% | 12 | 0.00% | 47.83% | 100.00% |
| scroll_feed_mobile | 7 | 46.15% | 5 | 14.29% | 32.00% | 0.00% |
| jpeg_feed_photo | 15 | 37.31% | 3 | 16.95% | 28.12% | 0.00% |
| jpeg_table_finance | 7 | 21.13% | 3 | 3.51% | 15.87% | 0.00% |
| modal_payment_mobile | 0 | 77.78% | 0 | 25.00% | 32.00% | 0.00% |
| search_command_dark | 14 | 16.67% | 7 | 7.41% | 11.11% | 0.00% |

## Overlay calibration

| Image | Excluded labels | Excluded missed in v1 | V1 recall | V2 recall |
|---|---:|---:|---:|---:|
| sheet_delete_modal | 20 | 19 | 11.54% | 50.00% |
| sheet_filters_mobile | 4 | 4 | 82.61% | 100.00% |
| modal_payment_mobile | 4 | 3 | 76.92% | 100.00% |
| search_command_dark | 15 | 15 | 12.12% | 22.22% |

## Crop request-quality observations

- `payment_confirm_mobile`: `asset_crop_2_be96b8ae9c2d3f1f` is integrity-valid but blank; classification: **fixed request targets blank region, not tool failure**.
- `list_notifications_mobile`: `asset_crop_2_be96b8ae9c2d3f1f` is integrity-valid but blank; classification: **fixed request targets blank region, not tool failure**.
