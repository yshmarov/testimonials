/*
 * testimonials widget — self-contained, no framework, no build step.
 *
 * Reads its config from the <script type="application/json"
 * data-testimonials-config> the server renders — re-read on every render so
 * a Turbo visit always reflects the current page's config.
 *
 * Nothing is visible until the widget opens: from the server (an eligible
 * `testimonial_prompt!` arrives as config.autoOpen), from any element carrying
 * `data-testimonial-prompt` (or `data-testimonial-prompt="nps"`), or from
 * window.Testimonials.open() / .openNps().
 *
 * Flow, modeled on iOS's "leave a review": a small star card first; tapping
 * a star expands into the full form (text or recorded video, consent, guest
 * contact fields). NPS asks 0–10, and promoters are offered the testimonial
 * form right after. Auto-opens report shown/dismissed to the throttle
 * ledger; explicit opens don't.
 *
 * On the public standalone pages the same code renders inline into
 * <div data-testimonials-inline>: the testimonial form (config.mode ===
 * "page") or the NPS card (config.mode === "nps_page").
 */
(function () {
  "use strict";

  var config = readConfig();
  if (!config || window.__testimonialsLoaded) return;
  window.__testimonialsLoaded = true;

  var Z = 2147482000;
  var overlay = null;
  var lastFocused = null;
  var savedOverflow = null; // documentElement overflow to restore when the modal closes
  var state = null; // one open session: { kind, auto, stage, rating, videoBlob, ... }
  var media = { stream: null, recorder: null, chunks: [], timer: null };
  var viewportHandler = null; // visualViewport listener while the dialog is open

  function ready(fn) {
    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", fn);
    } else {
      fn();
    }
  }

  ready(function () {
    document.addEventListener("keydown", handleKeydown);
    document.addEventListener("click", handleOpenerClick, true);

    render();
    document.addEventListener("turbo:load", render);

    window.Testimonials = {
      open: function () { openReview(false); },
      openNps: function () { openNps(false); }
    };
  });

  function readConfig() {
    var el = document.querySelector("script[data-testimonials-config]");
    if (!el) return null;
    try {
      return JSON.parse(el.textContent);
    } catch (e) {
      return null;
    }
  }

  function render() {
    config = readConfig() || config;
    injectStyles();

    // A Turbo body swap can remove the overlay without close() running; the
    // lock lives on documentElement, which survives the swap, so release it.
    if (!document.getElementById("tml-overlay")) unlockScroll();

    if (pageMode()) {
      renderInline();
      return;
    }

    // Each server-granted auto-open fires exactly once, even if Turbo
    // re-runs render() for the same document.
    var el = document.querySelector("script[data-testimonials-config]");
    if (config.autoOpen && el && !el.dataset.testimonialsHandled) {
      el.dataset.testimonialsHandled = "1";
      setTimeout(function () {
        if (config.autoOpen === "nps") openNps(true);
        else openReview(true);
      }, 600);
    }
  }

  function handleOpenerClick(event) {
    var opener = event.target && event.target.closest
      ? event.target.closest("[data-testimonial-prompt]")
      : null;
    if (!opener) return;
    event.preventDefault();
    event.stopPropagation();
    if (opener.getAttribute("data-testimonial-prompt") === "nps") openNps(false);
    else openReview(false);
  }

  function handleKeydown(event) {
    if (event.key === "Escape" && overlay) close();
  }

  // The backdrop only dismisses while nothing can be lost: the initial star
  // or NPS card, and the thanks screen. Once a form is on screen, closing
  // takes the × button (or Esc) — a stray click must not eat someone's
  // half-written testimonial.
  function dismissible() {
    return !state || state.submitted ||
      state.stage === "rate" || state.stage === "nps" || state.stage === "thanks";
  }

  // --- open / close -----------------------------------------------------------

  function openReview(auto) {
    if (!openSession("testimonial", auto)) return;
    if (config.existing) {
      // One review per user: editing replaces it, so skip the star card and
      // open the form pre-filled.
      prefillExisting();
      showStage(formStage(config.labels.updateTitle));
    } else {
      showStage(rateStage());
    }
  }

  function openNps(auto) {
    if (!config.nps.enabled) return openReview(auto);
    if (!openSession("nps", auto)) return;
    showStage(npsStage());
  }

  function openSession(kind, auto) {
    if (overlay) return false;
    state = { kind: kind, auto: !!auto, rating: 0, submitted: false, videoBlob: null, source: "widget" };
    lastFocused = document.activeElement;

    overlay = document.createElement("div");
    overlay.id = "tml-overlay";
    overlay.addEventListener("mousedown", function (event) {
      if (event.target === overlay && dismissible()) close();
    });

    var dialog = document.createElement("div");
    dialog.id = "tml-dialog";
    dialog.setAttribute("role", "dialog");
    dialog.setAttribute("aria-modal", "true");
    if (config.rtl) dialog.setAttribute("dir", "rtl");

    overlay.appendChild(dialog);
    document.body.appendChild(overlay);
    lockScroll();
    overlay.addEventListener("keydown", trapFocus);
    startViewportTracking();

    if (auto) postEvent(kind, "shown");
    return true;
  }

  // --- mobile keyboard --------------------------------------------------------
  // On phones the dialog is full-screen at height:100dvh, but iOS Safari shows
  // the on-screen keyboard WITHOUT resizing that fixed element — so the action
  // row gets hidden behind the keyboard. While the dialog is open we track
  // window.visualViewport and pin the full-screen overlay (and the dialog that
  // fills it) to the currently-visible area, so Submit/Cancel sit just above the
  // keyboard. The dialog itself is a static-positioned flex child, so `top` on
  // it does nothing — we move the fixed overlay for position and size the dialog
  // to match. Desktop is untouched: everything is gated on the mobile media
  // query, and browsers without visualViewport no-op (today's behavior).

  function applyViewport() {
    if (!overlay) return;
    var dialog = overlay.querySelector("#tml-dialog");
    var vv = window.visualViewport;
    if (vv && window.matchMedia("(max-width:480px)").matches) {
      overlay.style.top = vv.offsetTop + "px";
      overlay.style.height = vv.height + "px";
      overlay.style.bottom = "auto"; // height + top win; drop the inset:0 bottom
      if (dialog) dialog.style.height = vv.height + "px";
    } else {
      // Not the mobile full-screen layout: clear every override so the
      // stylesheet's centered desktop rules apply cleanly.
      overlay.style.top = "";
      overlay.style.height = "";
      overlay.style.bottom = "";
      if (dialog) dialog.style.height = "";
    }
  }

  function startViewportTracking() {
    if (!window.visualViewport) return;
    viewportHandler = function () { applyViewport(); };
    window.visualViewport.addEventListener("resize", viewportHandler);
    window.visualViewport.addEventListener("scroll", viewportHandler);
    applyViewport(); // pin once on open
  }

  function stopViewportTracking() {
    if (viewportHandler && window.visualViewport) {
      window.visualViewport.removeEventListener("resize", viewportHandler);
      window.visualViewport.removeEventListener("scroll", viewportHandler);
    }
    viewportHandler = null;
    // Clear inline styles so a later desktop open starts from the stylesheet.
    if (overlay) {
      overlay.style.top = "";
      overlay.style.height = "";
      overlay.style.bottom = "";
      var dialog = overlay.querySelector("#tml-dialog");
      if (dialog) dialog.style.height = "";
    }
  }

  function close() {
    if (!overlay) return;
    stopViewportTracking();
    stopMedia();
    if (state && state.playbackUrl) URL.revokeObjectURL(state.playbackUrl);
    if (state && state.posterUrl) URL.revokeObjectURL(state.posterUrl);
    if (state && state.auto && !state.submitted) postEvent(state.kind, "dismissed");
    overlay.remove();
    overlay = null;
    state = null;
    unlockScroll();
    if (lastFocused && lastFocused.focus) lastFocused.focus();
  }

  function lockScroll() {
    if (savedOverflow === null) savedOverflow = document.documentElement.style.overflow;
    document.documentElement.style.overflow = "hidden";
  }

  function unlockScroll() {
    if (savedOverflow === null) return;
    document.documentElement.style.overflow = savedOverflow;
    savedOverflow = null;
  }

  function dialogEl() {
    return overlay ? overlay.querySelector("#tml-dialog") : document.querySelector("[data-testimonials-inline] .tml-inline");
  }

  function showStage(node) {
    var dialog = dialogEl();
    if (!dialog) return;
    stopMedia();
    dialog.textContent = "";
    dialog.appendChild(node);
    var focusable = dialog.querySelector("textarea, input, button");
    if (focusable && overlay) {
      focusable.focus();
      // With the viewport pinned above the keyboard the shrink handles most of
      // it; nudge the focused field fully into view for the rest.
      if (focusable.scrollIntoView) focusable.scrollIntoView({ block: "nearest" });
    }
  }

  function trapFocus(event) {
    if (event.key !== "Tab" || !overlay) return;
    var focusable = overlay.querySelectorAll("button, select, textarea, input, a[href], video");
    if (!focusable.length) return;
    var first = focusable[0];
    var last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
  }

  // --- inline (the standalone public pages) -----------------------------------

  // A page IS the prompt: the visitor followed a link here, so there is no
  // overlay and nothing to dismiss — "Not now", Cancel and the × are omitted.
  function pageMode() {
    return config.mode === "page" || config.mode === "nps_page";
  }

  function renderInline() {
    var host = document.querySelector("[data-testimonials-inline]");
    if (!host || host.querySelector(".tml-inline")) return;
    var card = document.createElement("div");
    card.className = "tml-inline";
    if (config.rtl) card.setAttribute("dir", "rtl");
    host.appendChild(card);

    var nps = config.mode === "nps_page" && config.nps.enabled;
    state = { kind: nps ? "nps" : "testimonial", auto: false, rating: 0,
              submitted: false, videoBlob: null, source: "page" };
    if (nps) {
      card.appendChild(npsStage());
      return;
    }
    if (config.existing) prefillExisting();
    card.appendChild(formStage(config.existing ? config.labels.updateTitle : config.labels.shareTitle));
  }

  // --- stage 1: the iOS-style star card ---------------------------------------

  function rateStage() {
    state.stage = "rate";
    var stage = el("div", "tml-stage");
    stage.appendChild(el("h2", "tml-title", config.labels.enjoying));

    var stars = el("div", "tml-stars tml-stars-big");
    for (var i = 1; i <= 5; i++) {
      stars.appendChild(starButton(i, function (value) {
        state.rating = value;
        showStage(formStage(config.labels.shareTitle));
      }));
    }
    stage.appendChild(stars);
    stage.appendChild(notNowButton());
    return stage;
  }

  function starButton(value, onPick) {
    var button = el("button", "tml-star", "★");
    button.type = "button";
    button.setAttribute("aria-label", config.labels.rateAria.replace("%{count}", value));
    button.addEventListener("mouseenter", function () { paintStars(button.parentNode, value); });
    button.addEventListener("mouseleave", function () { paintStars(button.parentNode, state.rating); });
    button.addEventListener("click", function () {
      paintStars(button.parentNode, value);
      onPick(value);
    });
    return button;
  }

  function paintStars(container, upto) {
    var stars = container.querySelectorAll(".tml-star");
    for (var i = 0; i < stars.length; i++) {
      stars[i].classList.toggle("tml-star-on", i < upto);
    }
  }

  function notNowButton() {
    var button = el("button", "tml-plain", config.labels.notNow);
    button.type = "button";
    button.addEventListener("click", close);
    return button;
  }

  function prefillExisting() {
    state.rating = config.existing.rating || 0;
    state.body = config.existing.body || "";
    state.consent = !!config.existing.consent;
    state.existingVideoUrl = config.existing.videoUrl || null;
    state.existingPosterUrl = config.existing.posterUrl || null;
  }

  // --- stage 2: the testimonial form ------------------------------------------

  function formStage(title) {
    state.stage = "form";
    state.formTitle = title;
    var stage = el("div", "tml-stage");
    stage.appendChild(header(title));

    var form = document.createElement("form");
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      submitTestimonial(form);
    });

    var stars = el("div", "tml-stars");
    for (var i = 1; i <= 5; i++) {
      stars.appendChild(starButton(i, function (value) { state.rating = value; }));
    }
    paintStars(stars, state.rating);
    form.appendChild(stars);

    var questions = questionsBox();
    if (questions) form.appendChild(questions);

    // Video first: it's the submission we want most, and the inviting panel
    // reads as the primary path with text as the fallback below it.
    if (config.video.enabled) form.appendChild(videoControl(form));

    var textarea = document.createElement("textarea");
    textarea.name = "body";
    textarea.rows = 4;
    textarea.placeholder = config.labels.messagePlaceholder;
    textarea.value = state.body || "";
    form.appendChild(field(config.labels.message, textarea));
    if (!config.authenticated) {
      appendGuestFields(form);
      restoreDraftFields(form);
    }
    form.appendChild(consentField());

    var error = el("p", "tml-error");
    error.setAttribute("role", "alert");
    error.hidden = true;
    form.appendChild(error);

    var actions = el("div", "tml-actions");
    if (overlay) actions.appendChild(secondaryButton(config.labels.cancel, close));
    var submit = el("button", "tml-primary", config.labels.submit);
    submit.type = "submit";
    actions.appendChild(submit);
    form.appendChild(actions);

    stage.appendChild(form);
    return stage;
  }

  function appendGuestFields(form) {
    var name = document.createElement("input");
    name.type = "text";
    name.name = "name";
    name.autocomplete = "name";
    form.appendChild(field(config.labels.name, name));

    var email = document.createElement("input");
    email.type = "email";
    email.name = "email";
    email.autocomplete = "email";
    form.appendChild(field(config.labels.email, email));

    var title = document.createElement("input");
    title.type = "text";
    title.name = "title_company";
    title.autocomplete = "organization-title";
    form.appendChild(field(config.labels.titleCompany + " (" + config.labels.optional + ")", title));

    if (pageMode() && config.avatars.enabled) {
      var avatar = document.createElement("input");
      avatar.type = "file";
      avatar.name = "avatar";
      avatar.accept = "image/*";
      form.appendChild(field(config.labels.photo + " (" + config.labels.optional + ")", avatar));
    }
  }

  function questionsBox() {
    if (!config.questions.length) return null;
    var box = el("div", "tml-questions");
    box.appendChild(el("strong", null, config.labels.questionsTitle));
    var list = document.createElement("ul");
    config.questions.forEach(function (question) {
      list.appendChild(el("li", null, question));
    });
    box.appendChild(list);
    return box;
  }

  // Where may we use this? Public (shown in marketing, served by the read
  // API) or private (kept for internal use only). Public is the default —
  // someone leaving a testimonial usually expects it shown — but private is
  // an equally-visible, graceful choice, not a buried opt-out.
  function consentField() {
    var wrap = el("div", "tml-consent");
    if (config.consent.prompt) wrap.appendChild(el("p", "tml-consent-prompt", config.consent.prompt));
    // state.consent (a bool) survives stage round trips and reflects an
    // edited review's existing choice; undefined on a new review means public.
    wrap.appendChild(consentOption("public", config.consent.public, state.consent !== false));
    wrap.appendChild(consentOption("private", config.consent.private, state.consent === false));
    return wrap;
  }

  function consentOption(value, label, checked) {
    var opt = el("label", "tml-consent-option");
    var radio = document.createElement("input");
    radio.type = "radio";
    radio.name = "consent";
    radio.value = value;
    radio.checked = checked;
    radio.addEventListener("change", function () {
      if (radio.checked) state.consent = value === "public";
    });
    opt.appendChild(radio);
    opt.appendChild(el("span", null, label));
    return opt;
  }

  // --- video ------------------------------------------------------------------

  function videoControl(form) {
    var wrap = el("div", "tml-field");

    // A just-recorded or just-uploaded video: show it playable on the form,
    // not only as a chip — the same preview the review step showed, carried
    // over so "Use this video" doesn't make the clip visually vanish.
    if (state.videoBlob) {
      var recorded = document.createElement("video");
      recorded.className = "tml-video";
      recorded.controls = true;
      recorded.playsInline = true;
      recorded.preload = "metadata";
      // Fresh object URL for the current blob (revoked in close()); reuse the
      // captured poster so Safari paints a frame instead of black.
      if (state.playbackUrl) URL.revokeObjectURL(state.playbackUrl);
      state.playbackUrl = URL.createObjectURL(state.videoBlob);
      recorded.src = state.playbackUrl;
      if (state.posterBlob) {
        if (state.posterUrl) URL.revokeObjectURL(state.posterUrl);
        state.posterUrl = URL.createObjectURL(state.posterBlob);
        recorded.poster = state.posterUrl;
      }
      wrap.appendChild(videoPreview(form, wrap, recorded, function () {
        state.videoBlob = null;
      }));
      return wrap;
    }

    // Editing a review that already has a video: show it, playable, with a
    // remove control. Removing reveals the record panel again.
    if (state.existingVideoUrl && !state.removeExistingVideo) {
      var playback = document.createElement("video");
      playback.className = "tml-video";
      playback.controls = true;
      playback.playsInline = true;
      playback.preload = "metadata";
      // The stored poster shows a real frame with no decoding — the reliable
      // fix for Safari, which won't paint a fragmented-MP4 frame on its own.
      if (state.existingPosterUrl) playback.poster = state.existingPosterUrl;
      playback.src = state.existingVideoUrl;
      wrap.appendChild(videoPreview(form, wrap, playback, function () {
        state.removeExistingVideo = true;
      }));
      return wrap;
    }

    // The strongest testimonials are videos — this is a big, inviting
    // panel-button rather than a modest secondary action.
    var button = el("button", "tml-record");
    button.type = "button";
    button.appendChild(el("span", "tml-record-label", "🎥 " + config.labels.recordVideo));
    button.appendChild(el("span", "tml-record-hint", config.labels.recordVideoHint));
    button.addEventListener("click", function () {
      // The form is about to be replaced by the recorder — keep what the
      // user already typed so it survives the round trip.
      saveDraft(form);
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia && window.MediaRecorder) {
        showStage(videoStage());
      } else {
        pickVideoFile();
      }
    });
    wrap.appendChild(button);
    return wrap;
  }

  // A discreet "remove attachment" affordance: the video preview wrapped so a
  // small round ✕ can sit in its top-right corner (overlaid on the clip, clear
  // of the centered play button), instead of a full-width, easy-to-mis-tap row.
  function videoPreview(form, wrap, playback, onRemove) {
    var box = el("div", "tml-video-wrap");
    box.appendChild(playback);
    var remove = el("button", "tml-video-remove", "✕");
    remove.type = "button";
    remove.setAttribute("aria-label", config.labels.remove);
    remove.addEventListener("click", function () {
      onRemove();
      wrap.replaceWith(videoControl(form));
    });
    box.appendChild(remove);
    return box;
  }

  // Recording lives in its own stage: camera check -> 3-2-1 -> recording ->
  // review. The guiding questions stay pinned above the preview the whole
  // time, so nobody freezes on camera wondering what to say.
  function videoStage() {
    state.stage = "video";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.videoCheckTitle));

    var questions = questionsBox();
    if (questions) stage.appendChild(questions);

    var frame = el("div", "tml-preview");
    var preview = document.createElement("video");
    preview.className = "tml-video";
    preview.autoplay = true;
    preview.muted = true;
    preview.playsInline = true;
    frame.appendChild(preview);

    var timer = el("div", "tml-timer");
    timer.hidden = true;
    frame.appendChild(timer);

    var countdown = el("div", "tml-countdown");
    countdown.hidden = true;
    frame.appendChild(countdown);
    stage.appendChild(frame);

    var hint = el("p", "tml-hint", config.labels.videoHint);
    stage.appendChild(hint);

    var error = el("p", "tml-error");
    error.setAttribute("role", "alert");
    error.hidden = true;
    stage.appendChild(error);

    var actions = el("div", "tml-actions");
    var start = el("button", "tml-primary", config.labels.startRecording);
    start.type = "button";
    var stop = el("button", "tml-primary", config.labels.stopRecording);
    stop.type = "button";
    stop.hidden = true;
    var back = secondaryButton(config.labels.cancel, function () {
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    actions.appendChild(back);
    actions.appendChild(start);
    actions.appendChild(stop);
    stage.appendChild(actions);

    var upload = el("button", "tml-plain", config.labels.uploadInstead);
    upload.type = "button";
    upload.addEventListener("click", function () {
      stopMedia();
      pickVideoFile();
    });
    stage.appendChild(upload);

    navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 1280 }, height: { ideal: 720 }, frameRate: { ideal: 30 } },
      audio: true
    })
      .then(function (stream) {
        media.stream = stream;
        preview.srcObject = stream;
      })
      .catch(function () {
        error.textContent = config.labels.errorCamera;
        error.hidden = false;
        start.disabled = true;
      });

    start.addEventListener("click", function () {
      if (!media.stream) return;
      start.disabled = true;
      // Once recording is committed, the only ways out are Finish or Cancel.
      upload.hidden = true;
      runCountdown(countdown, 3, function () {
        start.hidden = true;
        stop.hidden = false;
        beginRecording(preview, timer, stop);
      });
    });

    stop.addEventListener("click", function () {
      if (media.recorder && media.recorder.state !== "inactive") media.recorder.stop();
      clearInterval(media.timer);
    });

    return stage;
  }

  function runCountdown(node, from, onDone) {
    var left = from;
    node.hidden = false;
    node.textContent = String(left);
    media.timer = setInterval(function () {
      left -= 1;
      if (left <= 0) {
        clearInterval(media.timer);
        // Clear the text as well as hiding: the overlay's display:flex rule
        // outranks the [hidden] UA style, so belt and braces.
        node.textContent = "";
        node.hidden = true;
        onDone();
      } else {
        node.textContent = String(left);
      }
    }, 800);
  }

  function beginRecording(preview, timer, stop) {
    media.chunks = [];
    var recorder;
    try {
      recorder = new MediaRecorder(media.stream, { mimeType: recordingMimeType() });
    } catch (e) {
      recorder = new MediaRecorder(media.stream);
    }
    media.recorder = recorder;
    recorder.addEventListener("dataavailable", function (event) {
      if (event.data && event.data.size) media.chunks.push(event.data);
    });
    recorder.addEventListener("stop", function () {
      // A teardown (Cancel, close) also stops the recorder — only a real
      // Finish, where this recorder is still the active one, goes to review.
      if (media.recorder !== recorder) return;
      // Grab a poster frame from the still-live preview stream *before*
      // showStage tears the camera down. Captured from the camera, never
      // from the recorded blob — seeking Safari's own fragmented MP4 to
      // paint a frame is exactly what fails (black or stall), so we store a
      // real image and hand it to <video poster>, which needs no decoding.
      capturePoster(preview);
      var type = recorder.mimeType || "video/webm";
      var blob = new Blob(media.chunks, { type: type.split(";")[0] });
      showStage(reviewStage(blob));
    });

    // Safari can mute or end the camera track mid-recording (its camera
    // pause UI, device handoff, another app grabbing the camera). The
    // recorder doesn't notice and keeps writing audio-only — a silently
    // corrupt file whose video freezes at that point. Fail visible instead:
    // finish the take immediately, so the user reviews a valid clip.
    var videoTrack = media.stream.getVideoTracks()[0];
    if (videoTrack) {
      var finishEarly = function () {
        if (media.recorder === recorder && recorder.state !== "inactive") stop.click();
      };
      videoTrack.addEventListener("mute", finishEarly);
      videoTrack.addEventListener("ended", finishEarly);
    }

    // A 1s timeslice keeps Safari's muxer flushing as it goes; the chunks
    // concatenate into the final blob.
    recorder.start(1000);
    startTimer(timer, function () { stop.click(); });
  }

  function recordingMimeType() {
    var candidates = ["video/mp4", "video/webm;codecs=vp9,opus", "video/webm"];
    for (var i = 0; i < candidates.length; i++) {
      if (window.MediaRecorder.isTypeSupported(candidates[i])) return candidates[i];
    }
    return "";
  }

  function startTimer(timer, onLimit) {
    var left = config.video.maxSeconds;
    timer.hidden = false;
    timer.textContent = "● " + formatSeconds(left);
    media.timer = setInterval(function () {
      left -= 1;
      timer.textContent = "● " + formatSeconds(left);
      if (left <= 0) {
        clearInterval(media.timer);
        onLimit();
      }
    }, 1000);
  }

  function formatSeconds(total) {
    var minutes = Math.floor(total / 60);
    var seconds = total % 60;
    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds;
  }

  function reviewStage(blob) {
    state.stage = "review";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.shareTitle));

    var playback = document.createElement("video");
    playback.className = "tml-video";
    playback.controls = true;
    playback.playsInline = true;
    // The playback URL lives on the session, NOT on `media`: showStage()
    // tears media down on every transition, which used to revoke this URL
    // the instant the review screen appeared (Safari: WebKitBlobResource
    // error 1, dead player). Revoked on close or when re-recording.
    if (state.playbackUrl) URL.revokeObjectURL(state.playbackUrl);
    state.playbackUrl = URL.createObjectURL(blob);
    // No #t=0.1 here, on purpose: seeking a blob of Safari's own fragmented
    // MP4 recording can stall the video track while audio keeps playing.
    // The captured poster (below) shows a frame without any decoding.
    playback.src = state.playbackUrl;
    if (state.posterBlob) {
      if (state.posterUrl) URL.revokeObjectURL(state.posterUrl);
      state.posterUrl = URL.createObjectURL(state.posterBlob);
      playback.poster = state.posterUrl;
    }
    stage.appendChild(playback);

    var error = el("p", "tml-error");
    error.setAttribute("role", "alert");
    error.hidden = true;
    stage.appendChild(error);

    var actions = el("div", "tml-actions");
    actions.appendChild(secondaryButton(config.labels.recordAgain, function () {
      showStage(videoStage());
    }));
    var use = el("button", "tml-primary", config.labels.useVideo);
    use.type = "button";
    use.addEventListener("click", function () {
      if (blob.size > config.video.maxSize) {
        error.textContent = config.labels.errorVideoTooLarge;
        error.hidden = false;
        return;
      }
      state.videoBlob = blob;
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    actions.appendChild(use);
    stage.appendChild(actions);
    return stage;
  }

  function pickVideoFile() {
    var input = document.createElement("input");
    input.type = "file";
    input.accept = "video/*";
    input.addEventListener("change", function () {
      var file = input.files && input.files[0];
      if (!file) return;
      state.videoBlob = file;
      // Recorded videos grab their poster from the live preview; uploaded
      // files have no live stream, so grab one from the file itself — else
      // Safari shows a black frame (it won't paint a posterless video).
      capturePosterFromFile(file);
      showStage(formStage(state.formTitle || config.labels.shareTitle));
    });
    input.click();
  }

  // Load an uploaded video offscreen, seek a hair past the start (frame 0 is
  // often black), and reuse capturePoster's canvas grab. Best-effort and
  // async — if the customer sends before it resolves, no poster, no harm.
  function capturePosterFromFile(file) {
    try {
      var url = URL.createObjectURL(file);
      var probe = document.createElement("video");
      probe.preload = "metadata";
      probe.muted = true;
      probe.playsInline = true;
      var cleanup = function () { try { URL.revokeObjectURL(url); } catch (e) { /* noop */ } };
      probe.addEventListener("loadeddata", function () {
        try { probe.currentTime = Math.min(0.1, (probe.duration || 1) / 2); } catch (e) { cleanup(); }
      });
      probe.addEventListener("seeked", function () { capturePoster(probe); cleanup(); });
      probe.addEventListener("error", cleanup);
      probe.src = url;
    } catch (e) { /* poster is best-effort */ }
  }

  function stopMedia() {
    if (media.timer) clearInterval(media.timer);
    if (media.recorder && media.recorder.state !== "inactive") {
      try { media.recorder.stop(); } catch (e) { /* already stopped */ }
    }
    if (media.stream) {
      media.stream.getTracks().forEach(function (track) { track.stop(); });
    }
    media = { stream: null, recorder: null, chunks: [], timer: null };
  }

  // Draw the current preview frame to a canvas *now* (synchronous, while the
  // stream is live) and encode it as a JPEG poster. The canvas keeps the
  // pixels, so the async toBlob is safe even after the camera stops.
  function capturePoster(preview) {
    try {
      var w = preview.videoWidth;
      var h = preview.videoHeight;
      if (!w || !h) return;
      var canvas = document.createElement("canvas");
      canvas.width = w;
      canvas.height = h;
      canvas.getContext("2d").drawImage(preview, 0, 0, w, h);
      canvas.toBlob(function (blob) {
        if (state && blob) state.posterBlob = blob;
      }, "image/jpeg", 0.8);
    } catch (e) { /* poster is best-effort; a black frame is not fatal */ }
  }

  // --- NPS ----------------------------------------------------------------------

  function npsStage() {
    state.stage = "nps";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.npsQuestion));

    var row = el("div", "tml-nps");
    for (var score = 0; score <= 10; score++) {
      row.appendChild(npsButton(score));
    }
    stage.appendChild(row);

    var legend = el("div", "tml-nps-legend");
    legend.appendChild(el("span", null, config.labels.npsLow));
    legend.appendChild(el("span", null, config.labels.npsHigh));
    stage.appendChild(legend);

    if (overlay) stage.appendChild(notNowButton());
    return stage;
  }

  function npsButton(score) {
    var button = el("button", "tml-nps-score", String(score));
    button.type = "button";
    button.addEventListener("click", function () {
      state.rating = score;
      showStage(npsCommentStage(score));
    });
    return button;
  }

  function npsCommentStage(score) {
    state.stage = "form";
    var stage = el("div", "tml-stage");
    stage.appendChild(header(config.labels.npsQuestion));

    var picked = el("div", "tml-nps-picked", String(score));
    stage.appendChild(picked);

    var form = document.createElement("form");
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      submitNps(form, score);
    });

    var textarea = document.createElement("textarea");
    textarea.name = "comment";
    textarea.rows = 3;
    form.appendChild(field(config.labels.npsCommentLabel + " (" + config.labels.optional + ")", textarea));

    if (!config.authenticated) {
      var email = document.createElement("input");
      email.type = "email";
      email.name = "email";
      email.autocomplete = "email";
      form.appendChild(field(config.labels.email + " (" + config.labels.optional + ")", email));
    }

    var error = el("p", "tml-error");
    error.setAttribute("role", "alert");
    error.hidden = true;
    form.appendChild(error);

    var actions = el("div", "tml-actions");
    // In the widget, Cancel closes. On the page there is nothing to close, so
    // it discards this score and goes back to the scale — a mis-tapped number
    // must not be a dead end.
    actions.appendChild(secondaryButton(config.labels.cancel, overlay ? close : function () {
      showStage(npsStage());
    }));
    var submit = el("button", "tml-primary", config.labels.submit);
    submit.type = "submit";
    actions.appendChild(submit);
    form.appendChild(actions);

    stage.appendChild(form);
    return stage;
  }

  function submitNps(form, score) {
    var data = new FormData();
    data.append("nps[score]", score);
    data.append("nps[comment]", form.querySelector("textarea[name=comment]").value.trim());
    var email = form.querySelector("input[name=email]");
    if (email && email.value) data.append("nps[email]", email.value.trim());
    data.append("nps[page_url]", window.location.href);

    postForm(config.endpoints.nps, data, form, function (body) {
      state.submitted = true;
      if (body && body.offer_testimonial) {
        // The server said this promoter is still eligible for a testimonial
        // ask; this second prompt is an auto-open, so it reports itself.
        state.kind = "testimonial";
        state.submitted = false;
        state.auto = true;
        state.rating = 0;
        state.source = "nps";
        postEvent("testimonial", "shown");
        showStage(formStage(config.labels.promoterTitle));
      } else {
        thanks();
      }
    });
  }

  // --- submit -------------------------------------------------------------------

  function submitTestimonial(form) {
    var body = form.querySelector("textarea[name=body]").value.trim();
    var keepsExistingVideo = state.existingVideoUrl && !state.removeExistingVideo && !state.videoBlob;
    if (!body && !state.videoBlob && !keepsExistingVideo) {
      return showError(form, config.labels.errorBlank);
    }

    if (!config.authenticated) {
      var name = form.querySelector("input[name=name]");
      var email = form.querySelector("input[name=email]");
      if (!name.value.trim() || !email.value.trim()) {
        return showError(form, config.labels.errorContact);
      }
    }

    var data = new FormData();
    data.append("testimonial[body]", body);
    if (state.rating) data.append("testimonial[rating]", state.rating);
    data.append("testimonial[consent_given]",
      form.querySelector("input[name=consent]:checked").value === "public" ? "1" : "0");
    data.append("testimonial[page_url]", window.location.href);
    data.append("testimonial[source]", state.source);
    ["name", "email", "title_company"].forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input && input.value.trim()) data.append("testimonial[" + key + "]", input.value.trim());
    });
    var avatar = form.querySelector("input[name=avatar]");
    if (avatar && avatar.files && avatar.files[0]) {
      data.append("testimonial[avatar]", avatar.files[0]);
    }
    if (state.videoBlob) {
      var extension = (state.videoBlob.type || "video/webm").indexOf("mp4") > -1 ? "mp4" : "webm";
      data.append("testimonial[video_file]", state.videoBlob, "testimonial." + extension);
      // The poster frame captured at record time, so the stored video shows
      // a real thumbnail instead of a black box in every browser.
      if (state.posterBlob) data.append("testimonial[poster]", state.posterBlob, "poster.jpg");
    } else if (state.removeExistingVideo) {
      data.append("testimonial[remove_video]", "1");
    }

    postForm(config.endpoints.testimonials, data, form, function () {
      state.submitted = true;
      thanks();
    });
  }

  function postForm(endpoint, data, form, onSuccess) {
    var submit = form.querySelector(".tml-primary");
    if (submit) submit.disabled = true;

    fetch(endpoint, {
      method: "POST",
      headers: csrfHeaders(),
      body: data,
      credentials: "same-origin"
    })
      .then(function (response) {
        if (response.ok) {
          return response.json().catch(function () { return {}; }).then(onSuccess);
        }
        return response
          .json()
          .catch(function () { return {}; })
          .then(function (body) {
            var messages = body && body.errors;
            showError(form, (messages && messages[0]) || config.labels.errorSave);
          });
      })
      .catch(function () {
        showError(form, config.labels.errorSave);
      })
      .finally(function () {
        if (submit) submit.disabled = false;
      });
  }

  function postEvent(kind, action) {
    var data = new FormData();
    data.append("kind", kind);
    data.append("event_action", action);
    fetch(config.endpoints.events, {
      method: "POST",
      headers: csrfHeaders(),
      body: data,
      credentials: "same-origin",
      keepalive: true
    }).catch(function () { /* the ledger is best-effort */ });
  }

  function thanks() {
    if (state) state.stage = "thanks";
    var dialog = dialogEl();
    if (!dialog) return;
    dialog.textContent = "";
    var note = el("div", "tml-thanks");
    note.appendChild(el("div", "tml-thanks-mark", "✓"));
    note.appendChild(el("p", null, config.labels.thanks));
    dialog.appendChild(note);
    if (overlay) setTimeout(close, 2200);
  }

  // --- drafts ---------------------------------------------------------------------

  function saveDraft(form) {
    var textarea = form.querySelector("textarea[name=body]");
    if (textarea) state.body = textarea.value;
    var consent = form.querySelector("input[name=consent]");
    if (consent) state.consent = consent.checked;
    state.fields = {};
    ["name", "email", "title_company"].forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input) state.fields[key] = input.value;
    });
  }

  function restoreDraftFields(form) {
    if (!state.fields) return;
    Object.keys(state.fields).forEach(function (key) {
      var input = form.querySelector('input[name="' + key + '"]');
      if (input) input.value = state.fields[key];
    });
  }

  // --- small helpers ------------------------------------------------------------

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  function header(title) {
    var head = el("div", "tml-head");
    head.appendChild(el("h2", "tml-title", title));
    if (overlay) {
      var closeButton = el("button", "tml-x", "×");
      closeButton.type = "button";
      closeButton.setAttribute("aria-label", config.labels.close);
      closeButton.addEventListener("click", close);
      head.appendChild(closeButton);
    }
    return head;
  }

  function field(labelText, control) {
    var wrap = el("label", "tml-field");
    wrap.appendChild(el("span", null, labelText));
    wrap.appendChild(control);
    return wrap;
  }

  function secondaryButton(text, onClick) {
    var button = el("button", "tml-secondary", text);
    button.type = "button";
    button.addEventListener("click", onClick);
    return button;
  }

  function csrfHeaders() {
    var meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? { "X-CSRF-Token": meta.content } : {};
  }

  function showError(form, text) {
    var error = form.querySelector(".tml-error");
    if (!error) return;
    // Unhide first: text landing in an already-exposed alert region is
    // reliably announced; revealing role+text together sometimes isn't.
    error.hidden = false;
    error.textContent = text;
  }

  // --- styles -------------------------------------------------------------------

  function injectStyles() {
    var css = [
      "#tml-overlay{position:fixed;inset:0;z-index:" + Z + ";background:rgba(0,0,0,.45);",
      "display:flex;align-items:center;justify-content:center;padding:16px}",
      "#tml-dialog,.tml-inline{width:100%;max-width:440px;max-height:92vh;overflow:auto;",
      "background:#fff;color:#1c2024;border-radius:14px;padding:20px;",
      "font:14px/1.5 system-ui,-apple-system,sans-serif;box-shadow:0 20px 60px rgba(0,0,0,.35)}",
      ".tml-inline{box-shadow:none;border:1px solid #e5e7eb;max-width:520px;margin:0 auto;",
      "max-height:none;overflow:visible}",
      ".tml-head{display:flex;align-items:flex-start;justify-content:space-between;gap:8px;margin:0 0 12px}",
      ".tml-title{margin:0;font-size:17px}",
      ".tml-x{border:0;background:none;font-size:22px;line-height:1;cursor:pointer;color:inherit;padding:2px 6px}",
      ".tml-stage>.tml-title{display:block;text-align:center;margin-bottom:12px}",
      ".tml-stars{display:flex;justify-content:center;gap:4px;margin:4px 0 12px}",
      ".tml-star{border:0;background:none;cursor:pointer;font-size:26px;line-height:1;padding:2px;color:#d1d5db}",
      ".tml-stars-big .tml-star{font-size:38px}",
      ".tml-star-on{color:#f59e0b}",
      ".tml-plain{display:block;margin:4px auto 0;border:0;background:none;cursor:pointer;",
      "color:#2563eb;font:inherit;padding:6px}",
      ".tml-questions{margin:0 0 12px;padding:10px 12px;border-radius:10px;background:rgba(37,99,235,.07);font-size:13px}",
      ".tml-questions strong{display:block;margin-bottom:4px;font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:#2563eb}",
      ".tml-questions ul{margin:0;padding-inline-start:18px}",
      ".tml-field{display:block;margin-bottom:12px}",
      ".tml-field>span{display:block;margin-bottom:4px;font-weight:600}",
      "#tml-dialog textarea,#tml-dialog input[type=text],#tml-dialog input[type=email],#tml-dialog input[type=file],",
      ".tml-inline textarea,.tml-inline input[type=text],.tml-inline input[type=email],.tml-inline input[type=file]",
      "{width:100%;box-sizing:border-box;padding:8px;border:1px solid #d1d5db;border-radius:8px;",
      "background:inherit;color:inherit;font:inherit}",
      ".tml-stage textarea{resize:vertical}",
      ".tml-consent{margin-bottom:12px;font-size:13px}",
      ".tml-consent-prompt{margin:0 0 6px;font-weight:600}",
      ".tml-consent-option{display:flex;gap:8px;align-items:flex-start;margin-bottom:6px;cursor:pointer}",
      ".tml-consent-option input{margin-top:3px}",
      ".tml-error{color:#dc2626;margin:0 0 12px}",
      ".tml-hint{color:#6b7280;font-size:13px;margin:8px 0}",
      ".tml-actions{display:flex;justify-content:flex-end;gap:8px;flex-wrap:wrap}",
      ".tml-actions button{padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-actions .tml-plain{margin:0}",
      ".tml-secondary{border:1px solid #d1d5db;background:none;color:inherit;padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-primary{border:0;background:#2563eb;color:#fff;font-weight:600;padding:8px 14px;border-radius:8px;cursor:pointer;font:inherit}",
      ".tml-primary:disabled{opacity:.6;cursor:default}",
      ".tml-record{display:flex;flex-direction:column;align-items:center;gap:2px;width:100%;",
      "padding:12px;border:1.5px dashed #2563eb;border-radius:10px;cursor:pointer;",
      "background:rgba(37,99,235,.06);font:inherit}",
      ".tml-record:hover{background:rgba(37,99,235,.12)}",
      ".tml-record-label{color:#2563eb;font-weight:600}",
      ".tml-record-hint{font-size:12px;color:#6b7280}",
      ".tml-video{display:block;width:100%;border-radius:10px;background:#000;aspect-ratio:4/3;margin:0 0 12px}",
      // A recorded/uploaded/existing clip with a discreet corner remove control.
      ".tml-video-wrap{position:relative;margin:0 0 12px}",
      ".tml-video-wrap .tml-video{margin:0}",
      ".tml-video-remove{position:absolute;top:8px;inset-inline-end:8px;width:28px;height:28px;padding:0;",
      "display:flex;align-items:center;justify-content:center;border:0;border-radius:50%;",
      "background:rgba(0,0,0,.6);color:#fff;font-size:15px;line-height:1;cursor:pointer}",
      ".tml-video-remove:hover{background:rgba(0,0,0,.8)}",
      ".tml-preview{position:relative;margin-bottom:4px}",
      ".tml-preview .tml-video{margin-bottom:0}",
      ".tml-timer{position:absolute;top:8px;inset-inline-end:8px;background:rgba(0,0,0,.55);color:#fff;",
      "padding:2px 10px;border-radius:999px;font-weight:600;font-size:13px}",
      ".tml-countdown{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;",
      "font-size:72px;font-weight:700;color:#fff;text-shadow:0 2px 16px rgba(0,0,0,.6)}",
      ".tml-countdown[hidden]{display:none}",
      ".tml-nps{display:flex;gap:4px;justify-content:center;flex-wrap:wrap;margin:4px 0 6px}",
      ".tml-nps-score{min-width:32px;padding:8px 0;border:1px solid #d1d5db;border-radius:8px;",
      "background:none;color:inherit;cursor:pointer;font:inherit}",
      ".tml-nps-score:hover{background:#2563eb;border-color:#2563eb;color:#fff}",
      ".tml-nps-legend{display:flex;justify-content:space-between;font-size:12px;color:#6b7280;margin-bottom:8px}",
      ".tml-nps-picked{width:44px;height:44px;margin:0 auto 12px;display:flex;align-items:center;justify-content:center;",
      "border-radius:10px;background:#2563eb;color:#fff;font-size:18px;font-weight:700}",
      ".tml-thanks{text-align:center;padding:16px 0}",
      ".tml-thanks-mark{width:44px;height:44px;margin:0 auto 10px;display:flex;align-items:center;justify-content:center;",
      "border-radius:50%;background:#16a34a;color:#fff;font-size:22px}",
      "@media (prefers-color-scheme:dark){",
      "#tml-dialog,.tml-inline{background:#1a1f26;color:#e6e8ea}",
      ".tml-inline{border-color:#2a313a}",
      "#tml-dialog textarea,#tml-dialog input[type=text],#tml-dialog input[type=email],#tml-dialog input[type=file],",
      ".tml-inline textarea,.tml-inline input[type=text],.tml-inline input[type=email],.tml-inline input[type=file]",
      "{border-color:#2a313a}",
      ".tml-secondary{border-color:#2a313a}",
      ".tml-star{color:#3a4149}",
      ".tml-star-on{color:#f59e0b}",
      ".tml-nps-score{border-color:#2a313a}",
      ".tml-record{border-color:#3b82f6;background:rgba(59,130,246,.1)}",
      ".tml-record:hover{background:rgba(59,130,246,.18)}",
      ".tml-record-label{color:#3b82f6}",
      ".tml-hint,.tml-nps-legend,.tml-record-hint{color:#9aa2ab}",
      "}",
      // The dialog is the scrollable region; keep its scroll from chaining
      // into the host page (rubber-banding through the backdrop on touch).
      "#tml-dialog{overscroll-behavior:contain}",
      // Full-screen on mobile — no bottom sheet, no animation. Placed last,
      // with selectors at least as specific as the desktop rules above, so
      // these declarations win the cascade at equal specificity.
      "@media (max-width:480px){",
      "#tml-overlay{padding:0;align-items:stretch;justify-content:stretch}",
      "#tml-dialog{left:0;right:0;top:0;bottom:0;width:100%;max-width:none;",
      "height:100vh;height:100dvh;max-height:100dvh;border-radius:0;margin:0}",
      // 16px stops iOS Safari's auto-zoom when a field gets focus.
      "#tml-dialog textarea,#tml-dialog input[type=text],#tml-dialog input[type=email],#tml-dialog select{font-size:16px}",
      // The action row has no padding of its own; give it the home-indicator
      // safe area so Submit/Cancel never sit under the bar.
      "#tml-dialog .tml-actions{padding-bottom:calc(0px + env(safe-area-inset-bottom))}",
      "}"
    ].join("");
    // Re-inject only when the CSS changed. Turbo keeps <head> across visits, so
    // a stale <style> would otherwise pin old CSS after a shipped update, even
    // while fresh widget.js runs — as self-freshening as the fingerprinted URL.
    var existing = document.getElementById("tml-styles");
    if (existing && existing.textContent === css) return;
    if (existing) existing.remove();

    var style = document.createElement("style");
    style.id = "tml-styles";
    style.textContent = css;
    document.head.appendChild(style);
  }
})();
