document.addEventListener('DOMContentLoaded', () => {

  const easeCubic = (t) => 1 - Math.pow(1 - t, 3);

  const revealElements = () => {
    document.querySelectorAll('.reveal').forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.top < window.innerHeight * 0.88) el.classList.add('visible');
    });
  };

  const observeSections = () => {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach(entry => {
        if (entry.isIntersecting) {
          entry.target.classList.add('visible');
          entry.target.querySelectorAll('.stat-number').forEach(counterEl => animateCounter(counterEl));
        }
      });
    }, { threshold: 0.2 });

    document.querySelectorAll('.section, .hero, .logos, .cta, .footer').forEach(el => {
      el.classList.add('reveal');
      observer.observe(el);
    });
    document.querySelectorAll('.stat-card').forEach(el => observer.observe(el));
  };

  const animateCounter = (el) => {
    if (el.dataset.animated) return;
    el.dataset.animated = 'true';
    const target = parseInt(el.dataset.target, 10);
    const duration = 1600;
    const start = performance.now();
    const update = (now) => {
      const t = Math.min((now - start) / duration, 1);
      el.textContent = Math.round(easeCubic(t) * target);
      if (t < 1) requestAnimationFrame(update);
      else el.textContent = target;
    };
    requestAnimationFrame(update);
  };

  const setupComparisons = () => {
    document.querySelectorAll('.compare-slider-container').forEach(container => {
      const range = container.querySelector('.compare-range');
      const before = container.querySelector('.compare-before-image');
      const handle = container.querySelector('.compare-handle');
      if (!range || !before || !handle) return;

      const sync = (val) => {
        const pct = parseInt(val, 10);
        before.style.clipPath = `inset(0 ${100 - pct}% 0 0)`;
        handle.style.left = `${pct}%`;
      };
      range.addEventListener('input', () => sync(range.value));
      sync(range.value);
    });
  };

  const navScroll = () => {
    const nav = document.getElementById('nav');
    const bar = document.getElementById('progressBar');
    const links = document.querySelectorAll('.nav-link');
    const sections = [];
    links.forEach(l => {
      const id = l.getAttribute('href');
      if (id?.startsWith('#')) sections.push(document.getElementById(id.slice(1)));
    });
    if (!nav) return;
    let lastScroll = 0;
    window.addEventListener('scroll', () => {
      const curr = window.scrollY;
      const dh = document.documentElement;
      const scrollPct = curr / (dh.scrollHeight - dh.clientHeight);
      if (bar) bar.style.width = `${Math.min(scrollPct * 100, 100)}%`;

      if (curr > 120) {
        nav.style.transform = curr > lastScroll ? 'translateY(-140%)' : 'translateY(0)';
      } else {
        nav.style.transform = 'translateY(0)';
      }
      lastScroll = curr;

      sections.forEach((sec, i) => {
        if (!sec) return;
        const rect = sec.getBoundingClientRect();
        links[i].style.color = rect.top < 200 && rect.bottom > 100 ? 'var(--text)' : '';
        links[i].style.background = rect.top < 200 && rect.bottom > 100 ? 'rgba(255,255,255,.5)' : '';
      });
    }, { passive: true });
  };

  const heroParallax = () => {
    const showcase = document.getElementById('heroShowcase');
    if (!showcase) return;
    let ticking = false;
    window.addEventListener('scroll', () => {
      if (!ticking) {
        requestAnimationFrame(() => {
          const rect = showcase.getBoundingClientRect();
          const center = rect.top + rect.height / 2;
          const viewCenter = window.innerHeight / 2;
          const offset = (center - viewCenter) * 0.03;
          showcase.style.transform = `translateY(${offset}px)`;
          ticking = false;
        });
        ticking = true;
      }
    }, { passive: true });
  };

  const initBadgeAnimation = () => {
    const beforeSize = document.getElementById('beforeSize');
    const afterSize = document.getElementById('afterSize');
    const metricValue = document.getElementById('panelMetric')?.querySelector('.metric-value');
    const panelBadge = document.getElementById('panelBadge');
    const barFill = document.querySelector('.after-row .bar-fill');
    if (!beforeSize) return;

    const animate = () => {
      beforeSize.textContent = '24 MB';
      if (!afterSize) return;
      let current = 24;
      const target = 0.14;
      const duration = 2000;
      const start = performance.now();
      const update = (now) => {
        const t = Math.min((now - start) / duration, 1);
        const eased = easeCubic(t);
        current = 24 - (24 - target) * eased;
        afterSize.textContent = current >= 1 ? `${Math.round(current)} MB` : `${Math.round(current * 1000)} KB`;
        if (metricValue) metricValue.textContent = `${((1 - current / 24) * 100).toFixed(1)}%`;
        if (barFill) barFill.style.width = `${(current / 24 * 100)}%`;
        if (t < 1) requestAnimationFrame(update);
        else {
          afterSize.textContent = '140 KB';
          if (metricValue) metricValue.textContent = '99.4%';
          if (barFill) barFill.style.width = '0.6%';
          if (panelBadge) panelBadge.style.opacity = '1';
        }
      };
      requestAnimationFrame(update);
    };

    const observer = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) {
        setTimeout(animate, 500);
        observer.disconnect();
      }
    }, { threshold: 0.3 });
    observer.observe(document.getElementById('mainPanel') || document.getElementById('hero'));
  };

  const smoothAnchors = () => {
    document.querySelectorAll('a[href^="#"]').forEach(a => {
      a.addEventListener('click', (e) => {
        const id = a.getAttribute('href');
        if (id === '#' || id.length < 2) return;
        const target = document.querySelector(id);
        if (target) {
          e.preventDefault();
          target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        }
      });
    });
  };

  const initQueuePanel = () => {
    const queueItems = document.querySelectorAll('.queue-panel-item');
    if (!queueItems.length) return;
    let idx = 2;
    setInterval(() => {
      queueItems.forEach((item, i) => {
        if (i === idx % queueItems.length) {
          item.classList.add('processing');
          const status = item.querySelector('.q-item-status');
          if (status) { status.textContent = 'Processing'; status.classList.remove('done'); }
        } else if (i === (idx - 1) % queueItems.length) {
          item.classList.remove('processing');
          const status = item.querySelector('.q-item-status');
          if (status) { status.textContent = 'Done'; status.classList.add('done'); }
        }
      });
      idx++;
    }, 2500);
  };

  observeSections();
  revealElements();
  setupComparisons();
  navScroll();
  heroParallax();
  initBadgeAnimation();
  smoothAnchors();
  initQueuePanel();

  window.addEventListener('scroll', revealElements, { passive: true });
  window.addEventListener('resize', revealElements, { passive: true });
});