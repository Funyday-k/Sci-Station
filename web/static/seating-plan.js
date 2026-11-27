"use strict";

(() => {
  const NS = "http://www.w3.org/2000/svg";
  const svg = (name, attributes = {}) => {
    const node = document.createElementNS(NS, name);
    for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
    return node;
  };

  // The table stays round for a small meeting. Larger groups use one extended
  // tabletop with semicircular ends, keeping chairs evenly spaced along its edge.
  const radius = 47, seatRadius = 65, margin = 30, centerY = 96;
  const arc = Math.PI * seatRadius;
  function position(index, count, extension) {
    const perimeter = 2 * (arc + extension);
    let distance = (perimeter * index / count + extension / 2) % perimeter;
    const left = margin + seatRadius, right = left + extension;
    if (distance <= extension)
      return {x:left + distance, y:centerY - seatRadius, angle:0};
    distance -= extension;
    if (distance <= arc) {
      const t = distance / seatRadius;
      return {x:right + seatRadius * Math.sin(t), y:centerY - seatRadius * Math.cos(t), angle:t * 180 / Math.PI};
    }
    distance -= arc;
    if (distance <= extension)
      return {x:right - distance, y:centerY + seatRadius, angle:180};
    const t = (distance - extension) / seatRadius;
    return {x:left - seatRadius * Math.sin(t), y:centerY + seatRadius * Math.cos(t), angle:180 + t * 180 / Math.PI};
  }

  const artwork = `
    <defs>
      <linearGradient id="table-surface" x1="0" x2=".75" y1="0" y2="1" gradientUnits="objectBoundingBox">
        <stop offset="0" class="wood-light"/><stop offset="1" class="wood-shade"/>
      </linearGradient>
      <clipPath id="table-edge-clip"><rect class="table-geometry" rx="47"/></clipPath>
      <pattern id="table-grain" width="92" height="28" patternUnits="userSpaceOnUse">
        <path d="M-2 10c14-2 21 2 35 2s27-5 60-2m-78 11c21-3 32 1 48-1m5-15 17 1" fill="none" class="table-grain" stroke-width=".65"/>
      </pattern>
    </defs>
    <g aria-hidden="true">
      <rect class="table-geometry table-shadow" rx="47" transform="translate(0 5)"/>
      <rect class="table-geometry table-edge" rx="47" transform="translate(0 2.5)"/>
      <rect class="table-geometry table-top" rx="47" fill="url(#table-surface)"/>
      <rect class="table-geometry" rx="47" fill="url(#table-grain)" clip-path="url(#table-edge-clip)"/>
    </g>
    <g class="table-objects" aria-hidden="true">
      <g transform="rotate(-16 -5 2)">
        <rect x="-11" y="-6" width="15" height="20" rx="2" class="notebook-shadow"/>
        <rect x="-12" y="-8" width="15" height="20" rx="2" class="notebook"/>
        <path d="M-8-8v20m3-13h5m-5 3h4" class="book-lines" fill="none"/>
      </g>
      <g transform="translate(11 -5)">
        <ellipse cy="1.7" rx="6.5" ry="5.5" class="cup-shadow"/>
        <path d="M3.7-2.5c6-2.2 7.6 5 .6 4.8" fill="none" class="cup-handle" stroke-width="2"/>
        <circle r="4.8" class="cup"/><circle r="3.1" class="coffee"/>
      </g>
    </g>
    <g class="seating-people"></g>`;

  const hairStyles = [
    '<path d="M-10-5c-1.5-8.8 3.7-14 11-13.1 7.5.4 11.2 6.6 9.1 13.3L7.4-8l-.7-2.8c-4 3-8.8 4-13.3 3.1L-9-3.3z"/>',
    '<path d="M-9.8-4.3c-2.1-3.2-1.7-7.5 0-9.1-.4-2.8 2.9-5.4 5.2-4.9 1.5-2.1 5.2-2.3 7.6-.7 3.9-1 6.8 1.3 7.5 3.8 2.4 1.4 2.5 5.6.7 8.2L8.4-4 7-9c-4.2 2.5-9 .7-11.7-.9L-7.6-7l-.5 3.1z"/>',
    '<circle cx="1" cy="-17.2" r="5"/><path d="M-10-5c-.9-7.2 2-13 10-13 7.8 0 11.4 5.8 10.1 13.1l-3-2.6-.6-3.1C2-7.1-3.3-8.1-7.5-7l-.8 4.2z"/>',
    '<path d="M-10-5.6c-.6-6.3 2.4-12.7 9.9-12.7 7.8 0 11.4 6.3 10.4 12.6L8-3.6 7-8.3C3.1-7.6.8-9.5-.5-11.4c-1.2 3.2-4 4.5-7.3 4.8L-8.5-3z"/>'
  ];
  const wardrobe = ["#557488","#9b695e","#647e70","#8b7198","#9a7949","#5e789e"];
  const complexions = [
    ["#e5b48d","#55392f"], ["#cf956f","#382f34"], ["#b87f5e","#322b2a"],
    ["#ecc5a4","#6a4a38"], ["#d9a682","#41322c"], ["#edc2ab","#61504b"]
  ];
  function artistSeed(key) {
    let n = 0;
    for (const letter of key) n = (Math.imul(31, n) + letter.codePointAt(0)) >>> 0;
    return n;
  }
  function createPerson(member, variant) {
    const group = svg("g", {class:"seated-person"});
    const title = svg("title");
    const figure = svg("g", {class:"seated-figure"});
    const mark = svg("g", {class:"person-brand"});
    const [skin,hair] = complexions[variant % complexions.length];
    figure.style.setProperty("--person-skin", skin);
    figure.style.setProperty("--person-hair", hair);
    figure.style.setProperty("--person-shirt", wardrobe[(variant >>> 5) % wardrobe.length]);
    /* html-sink: static built-in seating figure SVG artwork (no user data) */
    figure.innerHTML = `
      <ellipse cx="0" cy="-1" rx="18" ry="16" class="chair-shadow"/>
      <rect x="-15.5" y="-21" width="31" height="29" rx="10" class="chair-shell"/>
      <path d="M-13-11v-1.5c0-4.4 4-7.2 8.7-7.2h8.6c4.8 0 8.7 2.8 8.7 7.2v1.5" class="chair-seam" fill="none"/>
      <path d="M-16 4c.8-6 5.6-8.5 11-8.5h10c5.4 0 10.2 2.5 11 8.5l.6 9.5-7.6 1.5-1.5-6v7h-15v-7l-1.5 6-7.6-1.5z" class="person-shirt"/>
      <path d="M-15.2 12.6c1-1 3.8-.9 4.8.5l2.9 5c.7 1.3-.1 2.7-1.6 2.9-2.1.3-3.5-1.2-4.7-3.1l-1.7-2.4c-.8-1.2-.8-2.2.3-2.9zm30.4 0c-1-1-3.8-.9-4.8.5l-2.9 5c-.7 1.3.1 2.7 1.6 2.9 2.1.3 3.5-1.2 4.7-3.1l1.7-2.4c.8-1.2.8-2.2-.3-2.9z" class="person-skin"/>
      <path d="M-4.8-1h9.6v4c-1.8 3.3-7.8 3.3-9.6 0z" class="person-skin"/>
      <ellipse cx="-9" cy="-4.8" rx="2.6" ry="3.5" class="person-skin"/>
      <ellipse cx="9" cy="-4.8" rx="2.6" ry="3.5" class="person-skin"/>
      <ellipse cy="-6" rx="9.5" ry="10.2" class="person-skin"/>
      <g class="person-hair">${hairStyles[(variant >>> 2) % hairStyles.length]}</g>
      <path d="M-3-.4q3 1.8 6 0" fill="none" stroke="#76574c" stroke-width=".9" stroke-linecap="round"/>
      <g class="chief-star"><path d="m0-4 .95 2.55L3.6-.95 1.6.95l.35 2.7L0 2.3l-2 1.35.4-2.7-2-1.9 2.65-.5z"/></g>`;
    mark.append(svg("rect", {x:-9.6,y:-9.6,width:19.2,height:19.2,rx:6,class:"brand-tile"}));
    const image = svg("image", {x:-7.7,y:-7.7,width:15.4,height:15.4,preserveAspectRatio:"xMidYMid meet"});
    const neutral = svg("g", {class:"seat-model-icon", transform:"translate(-10 -10)"});
    const svg = window.RoundtableIcons?.iconNode?.("model"); if (svg) neutral.replaceChildren(svg);
    mark.append(image, neutral);
    figure.append(mark); group.append(title, figure);
    return {group, figure, mark, title, image, neutral, member, x:0, angle:0};
  }

  function mount(assetFor) {
    const root = document.getElementById("seating-room");
    const frame = document.getElementById("seating-scroll");
    const workspace = document.getElementById("seating-workspace");
    const pan = document.getElementById("seating-pan");
    const left = document.getElementById("seating-left");
    const right = document.getElementById("seating-right");
    /* html-sink: static built-in tabletop SVG artwork (no user data) */
    root.innerHTML = artwork;
    const geometry = root.querySelectorAll(".table-geometry");
    const props = root.querySelector(".table-objects");
    const layer = root.querySelector(".seating-people");
    const people = new Map();
    let width = 190, frameRequest = 0;
    function updatePan() {
      pan.hidden = frame.scrollWidth <= frame.clientWidth + 1;
      left.disabled = frame.scrollLeft <= 1;
      right.disabled = frame.scrollLeft >= frame.scrollWidth - frame.clientWidth - 1;
    }
    function shift(direction) {
      frame.scrollBy({left:direction * frame.clientWidth * .72, behavior:matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"});
    }
    left.addEventListener("click", () => shift(-1));
    right.addEventListener("click", () => shift(1));
    frame.addEventListener("scroll", updatePan, {passive:true});
    new ResizeObserver(updatePan).observe(frame);
    function highlight(member) {
      for (const person of people.values()) person.group.classList.toggle("is-emphasized", person.member === member);
    }
    function reveal(member) {
      highlight(member);
      const person = people.get(member);
      if (!person || frame.scrollWidth <= frame.clientWidth + 1) return;
      const screenX = person.x * root.getBoundingClientRect().width / width;
      if (screenX < frame.scrollLeft + 25 || screenX > frame.scrollLeft + frame.clientWidth - 25)
        frame.scrollLeft = screenX - frame.clientWidth / 2;
    }
    function render(members, catalog, changedMember) {
      const live = new Set(members);
      for (const [member, person] of people) {
        if (live.has(member)) continue;
        person.group.remove(); people.delete(member);
      }
      const extension = Math.max(0, (members.length * 47 - 2 * arc) / 2);
      width = 2 * (seatRadius + margin) + extension;
      const height = 192;
      root.setAttribute("viewBox", `0 0 ${width} ${height}`);
      root.setAttribute("aria-label", members.length ? `圆桌上有 ${members.length} 位参会成员，首席为${catalog.get(members[0].model)?.label || members[0].label || members[0].model}` : "空圆桌");
      root.style.width = `calc(var(--room-height) * ${width / height})`;
      workspace.classList.toggle("many-members", members.length > 8);
      const tableX = margin + seatRadius - radius;
      for (const part of geometry) {
        part.setAttribute("x", tableX); part.setAttribute("y", centerY - radius);
        part.setAttribute("width", 2 * radius + extension); part.setAttribute("height", 2 * radius);
      }
      props.setAttribute("transform", `translate(${width / 2} ${centerY})`);
      const occurrences = new Map();
      members.forEach((member, index) => {
        const model = catalog.get(member.model);
        const source = model?.source || member.source;
        const order = occurrences.get(member.model) || 0;
        occurrences.set(member.model, order + 1);
        let person = people.get(member);
        if (!person) {
          person = createPerson(member, artistSeed(member.model + "#" + order));
          people.set(member, person); layer.append(person.group);
        }
        const spot = position(index, members.length, extension);
        const turn = ((spot.angle - person.angle + 540) % 360 + 360) % 360 - 180;
        person.angle += turn;
        person.x = spot.x;
        person.group.style.transform = `translate(${spot.x}px,${spot.y}px)`;
        person.figure.style.transform = `rotate(${person.angle}deg)`;
        person.mark.style.transform = `translateY(15px) rotate(${-person.angle}deg)`;
        person.group.dataset.seat = index + 1;
        person.group.classList.toggle("is-chief", index === 0);
        person.title.textContent = `${index === 0 ? "首席" : "席位 " + (index + 1)} · ${model?.label || member.label || member.model}`;
        const src = assetFor(source);
        person.mark.classList.toggle("is-neutral", !src);
        if (src) person.image.setAttribute("href", src);
        else person.image.removeAttribute("href");
        person.image.setAttribute("visibility", src ? "visible" : "hidden");
        person.neutral.setAttribute("visibility", src ? "hidden" : "visible");
      });
      cancelAnimationFrame(frameRequest);
      frameRequest = requestAnimationFrame(() => {
        updatePan();
        if (changedMember) reveal(changedMember);
      });
    }
    return {render, highlight, reveal};
  }
  window.RoundtableSeating = Object.freeze({mount});
})();
