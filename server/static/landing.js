document.addEventListener('DOMContentLoaded', () => {

  const ease = [0.16, 1, 0.3, 1];

  const revealElements = () => {
    document.querySelectorAll('.reveal').forEach(el => {
      const rect = el.getBoundingClientRect();
      if (rect.top < window.innerHeight * 0.85) el.classList.add('visible');
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
      const eased = 1 - Math.pow(1 - t, 3);
      el.textContent = Math.round(eased * target);
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
    if (!nav) return;
    let lastScroll = 0;
    window.addEventListener('scroll', () => {
      const curr = window.scrollY;
      if (curr > 120) {
        nav.style.transform = curr > lastScroll ? 'translateY(-120%)' : 'translateY(0)';
      } else {
        nav.style.transform = 'translateY(0)';
      }
      lastScroll = curr;
    }, { passive: true });
  };

  const heroParallax = () => {
    const showcase = document.getElementById('heroShowcase');
    if (!showcase) return;
    window.addEventListener('scroll', () => {
      const rect = showcase.getBoundingClientRect();
      const center = rect.top + rect.height / 2;
      const viewCenter = window.innerHeight / 2;
      const offset = (center - viewCenter) * 0.03;
      showcase.style.transform = `translateY(${offset}px)`;
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
      if (afterSize) {
        let current = 24;
        const target = 0.14;
        const duration = 2000;
        const start = performance.now();
        const update = (now) => {
          const t = Math.min((now - start) / duration, 1);
          const eased = 1 - Math.pow(1 - t, 3);
          current = 24 - (24 - target) * eased;
          afterSize.textContent = current >= 1 ? `${Math.round(current)} MB` : `${Math.round(current * 10)} KB`;
          if (metricValue) metricValue.textContent = `${((1 - current / 24) * 100).toFixed(1)}%`;
          if (barFill) barFill.style.width = `${current / 24 * 100}%`;
          if (t < 1) requestAnimationFrame(update);
          else {
            afterSize.textContent = '140 KB';
            if (metricValue) metricValue.textContent = '99.4%';
            if (barFill) barFill.style.width = '0.6%';
            if (panelBadge) panelBadge.style.opacity = '1';
          }
        };
        requestAnimationFrame(update);
      }
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
        if (id === '#') return;
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

  const initMacDots = () => {
    const dots = document.querySelectorAll('.mac-dots span');
    if (!dots.length) return;
    setInterval(() => {
      dots[0].style.opacity = Math.random() > 0.5 ? '1' : '1';
    }, 3000);
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
