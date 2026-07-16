document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener('click', (event) => {
    const target = document.querySelector(link.getAttribute('href'));
    if (target) { event.preventDefault(); target.scrollIntoView({ behavior: 'smooth' }); }
  });
});

const observer = new IntersectionObserver((entries) => {
  entries.forEach((entry) => { if (entry.isIntersecting) entry.target.classList.add('revealed'); });
}, { threshold: 0.14 });
document.querySelectorAll('.feature, .principle-list article, .steps li').forEach((el) => observer.observe(el));
