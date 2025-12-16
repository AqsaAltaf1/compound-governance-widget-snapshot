# Tally Proposal Widget

A Discourse theme component that automatically detects Tally proposal URLs in posts and displays rich proposal information.

## Features

- Automatically detects Tally proposal URLs when pasted in Discourse posts
- Fetches proposal data from Tally GraphQL API
- Displays proposal title, status, and voting statistics
- Responsive design that works on mobile and desktop
- No backend required - all API calls are made client-side

## How It Works

1. When a user pastes a Tally proposal URL (e.g., `https://www.tally.xyz/proposal/[id]`) in a post
2. The component detects the URL using regex pattern matching
3. Extracts the proposal ID from the URL
4. Makes a GraphQL query to Tally API to fetch proposal data
5. Replaces the URL with a rich embed showing:
   - Proposal title
   - Current status
   - Voting statistics (For, Against, Abstain)
   - Link to view on Tally

## Installation

1. Upload this component to your Discourse instance
2. Enable it in your theme's component settings
3. The component will automatically start working - no configuration needed

## API Key

The component uses a Tally API key that is embedded in the JavaScript. If you need to use a different API key, edit the `TALLY_API_KEY` constant in `javascripts/discourse/api-initializers/tally-proposal-widget.gjs`.

## Supported URL Formats

- `https://www.tally.xyz/proposal/[id]`
- `https://tally.xyz/proposal/[id]`
- `https://www.tally.xyz/governance/[space]/proposal/[id]`

## Technical Details

- Uses Discourse's `apiInitializer` to hook into the post rendering system
- Uses `MutationObserver` to detect new posts dynamically
- GraphQL queries are made directly from the browser to Tally's API
- All styling uses Discourse's CSS variables for theme compatibility

