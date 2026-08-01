/*
 * testimonials dashboard helpers — CSP-safe replacements for inline
 * handlers, which strict script-src policies (nonce or 'self') block.
 *
 * forms with data-confirm ask before submitting; controls with
 * data-autosubmit submit their form on change. Document-level listeners,
 * registered once, so Turbo navigations into the dashboard are fine.
 */
(function () {
  "use strict";

  if (window.__testimonialsDashboardLoaded) return;
  window.__testimonialsDashboardLoaded = true;

  document.addEventListener("submit", function (event) {
    var form = event.target;
    var message = form && form.dataset ? form.dataset.confirm : null;
    if (message && !window.confirm(message)) {
      event.preventDefault();
      event.stopImmediatePropagation();
    }
  }, true);

  // Places the NPS score marker on the −100..100 scale. The position is a data
  // attribute rather than an inline style, which a strict style-src refuses.
  function placeNpsMarkers() {
    var markers = document.querySelectorAll("[data-nps-marker]");
    for (var i = 0; i < markers.length; i++) {
      var score = parseFloat(markers[i].getAttribute("data-nps-marker"));
      if (isNaN(score)) continue;
      markers[i].style.left = ((score + 100) / 2) + "%";
      markers[i].classList.add("placed");
    }
  }

  document.addEventListener("DOMContentLoaded", placeNpsMarkers);
  document.addEventListener("turbo:load", placeNpsMarkers);
  placeNpsMarkers();

  document.addEventListener("change", function (event) {
    var control = event.target;
    if (!control || !control.dataset || !control.dataset.autosubmit || !control.form) return;
    if (control.form.requestSubmit) {
      control.form.requestSubmit();
    } else {
      control.form.submit();
    }
  });
})();
