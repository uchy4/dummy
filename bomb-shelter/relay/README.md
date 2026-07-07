# Bomb Shelter internet relay

Lets a phone host a match for friends in other cities: the host connects
OUT to this Worker (no port forwarding, works on cell data), gets a short
room code, and remote friends play from their browser at
`https://<your-worker>/r/CODE`.

## One-time deploy (~2 minutes)

1. Install wrangler and log in to your (free) Cloudflare account:

       npm install -g wrangler
       wrangler login

2. Deploy from this directory:

       cd bomb-shelter/relay
       wrangler deploy

3. Wrangler prints the deployed URL, e.g.
   `https://bombshelter-relay.<your-subdomain>.workers.dev`.
   Put that hostname into `RELAY_HOST` in `bomb-shelter/scripts/net_hub.gd`
   (or tell Claude the URL and it will wire it in) and ship a new build.

Free-tier Durable Objects + Workers comfortably cover party-game traffic.
The relay stores nothing but the current game page per room; rooms are
ephemeral and die with the host's connection.
