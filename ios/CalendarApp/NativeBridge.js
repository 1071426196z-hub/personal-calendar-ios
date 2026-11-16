(() => {
  const dates = globalThis.CalendarDates;

  function span(time) {
    return {
      branch: time.getZhi(),
      ganzhi: time.getGanZhi(),
      start: time.getMinHm(),
      end: time.getMaxHm(),
      luck: time.getTianShenLuck(),
      yi: time.getYi(),
      ji: time.getJi(),
    };
  }

  globalThis.NativeCalendar = {
    dayInfo(key) {
      const info = dates.dayInfo(key);
      return JSON.stringify({ ...info, lunarText: dates.lunarText(info.moon) });
    },

    lunarDay(year, month, day, leap) {
      return JSON.stringify(dates.lunarToDate(year, { month, day, leap }));
    },

    nextLunarDay(month, day, leap, after) {
      return JSON.stringify(dates.nextLunar({ month, day, leap }, after));
    },

    occurrences(items, key) {
      return JSON.stringify(JSON.parse(items).filter((item) => dates.happensOn(item, key)).map((item) => item.id));
    },

    timedSegments(item, key) {
      return JSON.stringify(dates.timedSegments(JSON.parse(item), key));
    },

    upcoming(item, key) {
      return JSON.stringify(dates.upcoming(JSON.parse(item), key));
    },

    almanac(key, includeHours) {
      const lunar = globalThis.Solar.fromYmd(...dates.parts(key)).getLunar();
      return JSON.stringify({
        pillars: [
          lunar.getYearInGanZhi() + lunar.getYearShengXiao() + "年",
          lunar.getMonthInGanZhi() + "月",
          lunar.getDayInGanZhi() + "日",
        ].join(" · "),
        yi: lunar.getDayYi(),
        ji: lunar.getDayJi(),
        conflict: "冲" + lunar.getDayChongShengXiao() + " · 煞" + lunar.getDaySha(),
        guardian: lunar.getDayTianShen() + " · " + lunar.getDayTianShenType(),
        happiness: lunar.getDayPositionXiDesc(),
        wealth: lunar.getDayPositionCaiDesc(),
        hours: includeHours ? lunar.getTimes().map(span) : [],
      });
    },
  };
})();
