# Shared Protocol & Constants

Code placed here is loaded by both:
- `client/` (RGSS2 / Ruby 1.8.1)
- `server/` (Cross-platform standard Ruby 3.x)

**Important**: All `.rb` files in `shared/` MUST strictly use **Ruby 1.8.1-compatible syntax** (e.g., `:key => value` instead of `key: value`, no `require_relative`, no `&.`).
