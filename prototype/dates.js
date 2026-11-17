/* Civil dates are ISO strings. UTC arithmetic keeps day counts independent of daylight saving time. */
(() => {
  const DAY = 86_400_000;
  const MIN = "1901-01-01";
  const MAX = "2100-12-31";
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];
  const lunarMonths = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "冬月", "腊月"];
  const monthNumbers = new Map(lunarMonths.map((name, index) => [name, index + 1]));
  monthNumbers.set("十一月", 11);
  monthNumbers.set("十二月", 12);
  const numbers = "一二三四五六七八九";
  const lunarDays = Array.from({ length: 30 }, (_, index) => {
    const day = index + 1;
    if (day < 10) return "初" + numbers[index];
    if (day === 10) return "初十";
    if (day < 20) return "十" + numbers[index - 10];
    if (day === 20) return "二十";
    return day === 30 ? "三十" : "廿" + numbers[index - 20];
  });
  const lunarFormatter = typeof Intl === "object" && typeof Intl.DateTimeFormat === "function"
    ? new Intl.DateTimeFormat("zh-CN-u-ca-chinese", { year: "numeric", month: "numeric", day: "numeric", timeZone: "UTC" })
    : null;
  const hasChineseCalendar = lunarFormatter?.resolvedOptions().calendar === "chinese";
  const lunarCache = new Map();
  const lunarYearCache = new Map();

  const iso = (date) => date.toISOString().slice(0, 10);
  const make = (year, month, day) => iso(new Date(Date.UTC(year, month - 1, day)));
  const parse = (key) => new Date(key + "T00:00:00Z");
  const parts = (key) => key.split("-").map(Number);
  const add = (key, days) => iso(new Date(parse(key).getTime() + days * DAY));
  const weekday = (key) => parse(key).getUTCDay();
  const between = (from, to) => (parse(to) - parse(from)) / DAY;
  const weekStart = (key) => add(key, -((weekday(key) + 6) % 7));
  const daysInMonth = (year, month) => new Date(Date.UTC(year, month, 0)).getUTCDate();
  const valid = (key) => /^\d{4}-\d{2}-\d{2}$/.test(key) && key >= MIN && key <= MAX &&
    Number.isFinite(parse(key).valueOf()) && iso(parse(key)) === key;

  // Authoritative month boundaries for the two years with holiday data. The browser's
  // Chinese calendar can disagree with the published tables near midnight new moons.
  // https://www.hko.gov.hk/en/gts/time/calendar/text/files/T2027e.txt
  const verifiedMonths = [
    [2025, ["2025-12-20", "2026-01-19"], 11],
    [2026, ["2026-02-17", "2026-03-19", "2026-04-17", "2026-05-17", "2026-06-15", "2026-07-14",
      "2026-08-13", "2026-09-11", "2026-10-10", "2026-11-09", "2026-12-09", "2027-01-08"], 1],
    [2027, ["2027-02-06", "2027-03-08", "2027-04-07", "2027-05-06", "2027-06-05", "2027-07-04",
      "2027-08-02", "2027-09-01", "2027-09-30", "2027-10-29", "2027-11-28", "2027-12-28"], 1],
    [2028, ["2028-01-26"], 1],
  ].flatMap(([year, starts, firstMonth]) => starts.map((start, index) => ({
    start, year, month: firstMonth + index, leap: false,
  })));

  function today() {
    const now = new Date();
    return make(now.getFullYear(), now.getMonth() + 1, now.getDate());
  }

  function shiftMonth(key, shift) {
    const [year, month, day] = parts(key);
    const target = new Date(Date.UTC(year, month - 1 + shift, 1));
    const targetYear = target.getUTCFullYear();
    const targetMonth = target.getUTCMonth() + 1;
    return make(targetYear, targetMonth, Math.min(day, daysInMonth(targetYear, targetMonth)));
  }

  function withYear(key, year) {
    const [, month, day] = parts(key);
    return make(year, month, Math.min(day, daysInMonth(year, month)));
  }

  function dateText(key, includeYear = false) {
    const [year, month, day] = parts(key);
    return (includeYear ? year + "年" : "") + month + "月" + day + "日";
  }

  function lunar(key) {
    if (!lunarCache.has(key)) {
      const verified = key < "2028-02-25" && verifiedMonths.findLast(({ start }) => start <= key);
      if (verified) {
        const { year, month, leap, start } = verified;
        const result = { year, month, leap, day: between(start, key) + 1 };
        lunarCache.set(key, result);
        return result;
      }
      if (!hasChineseCalendar) {
        const date = globalThis.Solar.fromYmd(...parts(key)).getLunar();
        const result = { year: date.getYear(), month: Math.abs(date.getMonth()), day: date.getDay(), leap: date.getMonth() < 0 };
        lunarCache.set(key, result);
        return result;
      }
      const fields = Object.fromEntries(lunarFormatter.formatToParts(parse(key)).map(({ type, value }) => [type, value]));
      const leap = fields.month.startsWith("闰");
      const month = monthNumbers.get(fields.month.replace(/^闰/, ""));
      lunarCache.set(key, { year: Number(fields.relatedYear), month, day: Number(fields.day), leap });
    }
    return lunarCache.get(key);
  }

  function lunarText({ month, day, leap }) {
    return (leap ? "闰" : "") + lunarMonths[month - 1] + lunarDays[day - 1];
  }

  function lunarYear(year) {
    if (!lunarYearCache.has(year)) {
      const months = new Map();
      const end = make(year + 1, 3, 1);
      for (let key = make(year, 1, 15); key < end; key = add(key, 1)) {
        const date = lunar(key);
        if (date.year > year) break;
        if (date.year === year && date.day === 1) {
          months.set(date.month + ":" + date.leap, key);
        }
      }
      lunarYearCache.set(year, months);
    }
    return lunarYearCache.get(year);
  }

  function lunarToDate(year, { month, day, leap }) {
    const months = lunarYear(year);
    const first = (leap && months.get(month + ":true")) || months.get(month + ":false");
    if (!first) return null;
    const lastPossibleDay = add(first, 29);
    const monthLength = lunar(lastPossibleDay).day === 30 ? 30 : 29;
    return add(first, Math.min(day, monthLength) - 1);
  }

  function nextLunar(fields, from) {
    const year = lunar(from).year;
    const candidate = lunarToDate(year, fields);
    return candidate && candidate >= from ? candidate : lunarToDate(year + 1, fields);
  }

  const fixedFestivals = {
    "01-01": "元旦", "02-14": "情人节", "03-08": "妇女节", "03-12": "植树节",
    "04-01": "愚人节", "05-01": "劳动节", "05-04": "青年节", "06-01": "儿童节", "09-10": "教师节",
    "10-01": "国庆节", "10-31": "万圣节", "12-24": "平安夜", "12-25": "圣诞节", "12-31": "跨年夜",
  };

  function weekdayFestival(key) {
    const [year, month, day] = parts(key);
    const dayOfWeek = weekday(key);
    if ((month === 3 || month === 4) && dayOfWeek === 0 && key === westernEaster(year)) return "复活节";
    if (month === 5 && dayOfWeek === 0 && day >= 8 && day <= 14) return "母亲节";
    if (month === 6 && dayOfWeek === 0 && day >= 15 && day <= 21) return "父亲节";
    if (month === 11 && dayOfWeek === 4 && day >= 22 && day <= 28) return "感恩节";
    return "";
  }

  function westernEaster(year) {
    // Oudin's Gregorian Easter algorithm, as published by the U.S. Naval Observatory.
    const div = (value, divisor) => Math.trunc(value / divisor);
    const century = div(year, 100);
    const cycle = year % 19;
    const correction = div(century - 17, 25);
    let moon = (century - div(century, 4) - div(century - correction, 3) + 19 * cycle + 15) % 30;
    moon -= div(moon, 28) * (1 - div(moon, 28) * div(29, moon + 1) * div(21 - cycle, 11));
    const weekdayCorrection = (year + div(year, 4) + moon + 2 - century + div(century, 4)) % 7;
    const offset = moon - weekdayCorrection;
    const month = 3 + div(offset + 40, 44);
    return make(year, month, offset + 28 - 31 * div(month, 4));
  }
  const lunarFestivals = {
    "1-1": "春节", "1-15": "元宵节", "2-2": "龙抬头", "5-5": "端午节",
    "7-7": "七夕", "7-15": "中元节", "8-15": "中秋节", "9-9": "重阳节", "12-8": "腊八节",
  };
  // Hong Kong Observatory 2026 almanac and 2027 Gregorian–lunar conversion table (UTC+8).
  const termNames = ["小寒", "大寒", "立春", "雨水", "惊蛰", "春分", "清明", "谷雨", "立夏", "小满", "芒种", "夏至", "小暑", "大暑", "立秋", "处暑", "白露", "秋分", "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"];
  const termDates = {
    2026: [5, 20, 4, 18, 5, 20, 5, 20, 5, 21, 5, 21, 7, 23, 7, 23, 7, 23, 8, 23, 7, 22, 7, 22],
    2027: [5, 20, 4, 19, 6, 21, 5, 20, 6, 21, 6, 21, 7, 23, 8, 23, 8, 23, 8, 23, 7, 22, 7, 22],
  };
  const terms = new Map(Object.entries(termDates).flatMap(([year, days]) =>
    days.map((day, index) => [make(Number(year), Math.floor(index / 2) + 1, day), termNames[index]])));

  // Annual State Council holiday notices. Saturdays and Sundays without an entry stay unmarked.
  const restRanges = [
    ["2026-01-01", "2026-01-03", "元旦"], ["2026-02-15", "2026-02-23", "春节"],
    ["2026-04-04", "2026-04-06", "清明节"], ["2026-05-01", "2026-05-05", "劳动节"],
    ["2026-06-19", "2026-06-21", "端午节"], ["2026-09-25", "2026-09-27", "中秋节"],
    ["2026-10-01", "2026-10-07", "国庆节"], ["2027-01-01", "2027-01-03", "元旦"],
    ["2027-02-05", "2027-02-13", "春节"], ["2027-04-03", "2027-04-05", "清明节"],
    ["2027-05-01", "2027-05-05", "劳动节"], ["2027-06-09", "2027-06-09", "端午节"],
    ["2027-09-15", "2027-09-15", "中秋节"], ["2027-10-01", "2027-10-07", "国庆节"],
  ];
  const workdays = new Set([
    "2026-01-04", "2026-02-14", "2026-02-28", "2026-05-09", "2026-09-20", "2026-10-10",
    "2027-01-31", "2027-02-14", "2027-05-08", "2027-09-26", "2027-10-09",
  ]);

  function dayInfo(key) {
    const moon = lunar(key);
    const term = terms.get(key);
    const tomorrow = moon.month === 12 && moon.day >= 29 ? lunar(add(key, 1)) : null;
    const newYearEve = tomorrow?.month === 1 && !tomorrow.leap && tomorrow.day === 1;
    const traditional = !moon.leap && lunarFestivals[moon.month + "-" + moon.day];
    const festivals = new Set([
      newYearEve ? "除夕" : "", traditional || "", fixedFestivals[key.slice(5)] || "",
      term === "清明" ? "清明节" : "", weekdayFestival(key),
    ]);
    festivals.delete("");
    const [mainFestival] = festivals;
    const festival = [...festivals].join(" · ");
    const rest = restRanges.find(([from, to]) => key >= from && key <= to);
    return {
      moon, term, festival, shift: workdays.has(key) ? "班" : rest ? "休" : "",
      shiftText: workdays.has(key) ? "调休上班" : rest ? rest[2] + "放假" : "",
      shortLabel: mainFestival || term || (moon.day === 1 ? (moon.leap ? "闰" : "") + lunarMonths[moon.month - 1] : lunarDays[moon.day - 1]),
    };
  }

  const minutes = (time) => {
    const [hour, minute] = time.split(":").map(Number);
    return hour * 60 + minute;
  };

  function previousEventStart(item, key) {
    const [year, month] = parts(key);
    const [startYear, startMonth] = parts(item.date);
    switch (item.repeat) {
      case "daily": return key;
      case "weekly": return add(key, -(between(item.date, key) % 7));
      case "monthly": {
        const offset = (year - startYear) * 12 + month - startMonth;
        const candidate = shiftMonth(item.date, offset);
        return candidate > key ? shiftMonth(item.date, offset - 1) : candidate;
      }
      case "yearly": {
        const candidate = withYear(item.date, year);
        return candidate > key ? withYear(item.date, year - 1) : candidate;
      }
      default: return item.date;
    }
  }

  function happensOn(item, key) {
    if (key < item.date) return false;
    if (item.kind === "event") {
      const duration = between(item.date, item.endDate);
      const start = previousEventStart(item, key);
      const offset = between(start, key);
      return start >= item.date && (offset < duration || (offset === duration && (item.allDay || item.end !== "00:00")));
    }
    if (item.kind === "birthday" || (item.kind === "anniversary" && item.annual)) {
      return item.lunar ? lunarToDate(lunar(key).year, item.lunar) === key : withYear(item.date, parts(key)[0]) === key;
    }
    return item.date === key;
  }

  function timedSegments(item, key) {
    const dayMinutes = 24 * 60;
    const startTime = minutes(item.start);
    const length = between(item.date, item.endDate) * dayMinutes + minutes(item.end) - startTime;
    const segments = [];
    for (let day = key; day >= item.date;) {
      const start = previousEventStart(item, day);
      const from = startTime - between(start, key) * dayMinutes;
      const to = Math.min(dayMinutes, from + length);
      if (start < item.date || to <= 0) break;
      segments.push({ from: Math.max(0, from), to });
      day = add(start, -1);
    }
    return segments;
  }

  function upcoming(item, from) {
    if (item.date >= from) return item.date;
    if (item.kind === "birthday" || (item.kind === "anniversary" && item.annual)) {
      if (item.lunar) return nextLunar(item.lunar, from);
      const year = parts(from)[0];
      const candidate = withYear(item.date, year);
      return candidate >= from ? candidate : withYear(item.date, year + 1);
    }
    return item.date;
  }

  globalThis.CalendarDates = {
    MIN, MAX, weekdays, lunarMonths, lunarDays, make, parts, valid, add, weekday, between, weekStart,
    daysInMonth, today, shiftMonth, dateText, lunar, lunarText, lunarToDate, nextLunar,
    dayInfo, minutes, happensOn, timedSegments, upcoming,
  };
})();
