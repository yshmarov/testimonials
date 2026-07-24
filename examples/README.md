# Display examples

testimonials deliberately ships **no display UI** — approved testimonials are
yours to render, via `Testimonials::Testimonial.publishable` inside the app or
via the JSON API anywhere else. These files are copy-paste starting points so
you can see the end result in minutes. Take them, restyle them, own them.

| File | What it renders |
| --- | --- |
| [`wall_of_love.html.erb`](wall_of_love.html.erb) | A responsive grid of text + video testimonials |
| [`testimonial_card.html.erb`](testimonial_card.html.erb) | A single quote card for a landing/pricing page |
| [`badge.html.erb`](badge.html.erb) | The "★ 4.9 from 87 reviews" chip |
| [`json_ld.html.erb`](json_ld.html.erb) | schema.org AggregateRating + Review markup for Google rich snippets |
| [`static_site.md`](static_site.md) | Rendering testimonials on a separate marketing site (Astro & friends) from the public API |

In-app examples read the models directly — no HTTP, no `public_api` needed.
The static-site example is the one place the public API earns its keep.
