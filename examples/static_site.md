# Testimonials on a separate marketing site

Your Rails app collects and curates; your marketing site (Astro, Eleventy,
plain HTML on Cloudflare — anything) renders. Turn on the public API:

```ruby
# config/initializers/review_engine.rb
config.public_api = true
```

`GET https://app.example.com/reviews/api/testimonials` now serves approved +
consented records to anyone (CORS `*`), and `/reviews/api/stats` serves the
badge numbers. Emails are never included.

## Astro example (build-time fetch)

```astro
---
const res = await fetch("https://app.example.com/reviews/api/testimonials?limit=12");
const { testimonials } = await res.json();
const stats = await (await fetch("https://app.example.com/reviews/api/stats")).json();
---

<p>★ {stats.average_rating} from {stats.count} reviews</p>

<div class="wall">
  {testimonials.map((t) => (
    <figure>
      {t.rating && <div>{"★".repeat(t.rating)}</div>}
      {t.video_url && <video controls preload="metadata" src={t.video_url}></video>}
      {t.quote && <blockquote>“{t.quote}”</blockquote>}
      <figcaption>
        {t.avatar_url && <img src={t.avatar_url} alt="" width="36" height="36" />}
        <b>{t.name}</b> {t.title_company && <span>— {t.title_company}</span>}
      </figcaption>
    </figure>
  ))}
</div>
```

Media URLs (`video_url`, `avatar_url`) point back at the Rails app, which
redirects to signed Active Storage URLs with Range support — videos play
directly in a `<video>` tag.
