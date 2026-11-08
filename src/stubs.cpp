// Third-party DLLs GH3.exe imports that have nothing to do on this
// platform, reimplemented as the "unavailable" case the game already
// handles:
// - mac3r.dll, Massive AdClient 3 (in-game advertising; the service is
//   long gone). Initialize returns NULL, which GH3 stores at [obj+0x12f8]
//   and checks before every use (0x5138c0, 0x513ac0, 0xd9dfdb, 0xd9dff4),
//   so ads stay off. The ad-surface subscriber objects are inert.
// - IntelLaptopGaming.dll, Intel's laptop gaming SDK (battery and Wi-Fi
//   status for the menu): a desktop on AC power, full battery, no Wi-Fi.
// Statics are cdecl (caller pops: 0 stack arguments to declare); member
// functions are thiscall (this in ecx, callee pops its stack arguments).

#include "win32/hle.h"
#include "win32/kernel32_state.h"

namespace recomp::hle {

// ---- mac3r.dll (Massive AdClient 3) ----------------------------------------------

HLE_NAMED("mac3r.dll",
          "?Initialize@CMassiveClientCore@MassiveAdClient3@@SAPAV12@PAU__MAD_MASSIVE_INIT_"
          "STRUCT@2@@Z",
          MassiveInitialize, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll", "?Shutdown@CMassiveClientCore@MassiveAdClient3@@SAHHI@Z",
          MassiveShutdown, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll", "?Tick@CMassiveClientCore@MassiveAdClient3@@SAHH@Z", MassiveTick, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll", "?EnterZone@CMassiveClientCore@MassiveAdClient3@@SAHPBD@Z",
          MassiveEnterZone, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll", "?ExitZone@CMassiveClientCore@MassiveAdClient3@@SAHPBD@Z",
          MassiveExitZone, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll", "?FlushImpressions@CMassiveClientCore@MassiveAdClient3@@SAHXZ",
          MassiveFlushImpressions, 0) {
  return 0;
}
// CMassiveAdObjectSubscriber(const char* name): returns this.
HLE_NAMED("mac3r.dll", "??0CMassiveAdObjectSubscriber@MassiveAdClient3@@QAE@PBD@Z",
          MassiveSubscriberCtor, 1) {
  return uint32_t(c.ecx);
}
HLE_NAMED("mac3r.dll", "??1CMassiveAdObjectSubscriber@MassiveAdClient3@@QAE@XZ",
          MassiveSubscriberDtor, 0) {
  return 0;
}
HLE_NAMED("mac3r.dll",
          "?SetImpression@CMassiveAdObjectSubscriber@MassiveAdClient3@@QAEXPAU_MAD_"
          "Impression@2@@Z",
          MassiveSetImpression, 1) {
  return 0;
}

// ---- IntelLaptopGaming.dll ---------------------------------------------------------

// static GetTDKInterface(): the SDK's singleton; its methods ignore it.
HLE_NAMED("intellaptopgaming.dll",
          "?GetTDKInterface@IntelLaptopGamingTDKInterface@@SAPAV1@XZ", IntelGetTDKInterface,
          0) {
  static const gaddr instance = HeapAllocProcess(16, true);
  return instance;
}
HLE_NAMED("intellaptopgaming.dll", "?IsLaptop@IntelLaptopGamingTDKInterface@@QAE_NXZ",
          IntelIsLaptop, 0) {
  return 0;
}
HLE_NAMED("intellaptopgaming.dll",
          "?GetPercentBatteryLife@IntelLaptopGamingTDKInterface@@QAEHXZ",
          IntelGetPercentBatteryLife, 0) {
  return 100;
}
// PowerSource: 0 = AC (mains).
HLE_NAMED("intellaptopgaming.dll",
          "?GetPowerSrc@IntelLaptopGamingTDKInterface@@QAE?AW4PowerSource@@XZ",
          IntelGetPowerSrc, 0) {
  return 0;
}
HLE_NAMED("intellaptopgaming.dll",
          "?Get80211SignalStrength@IntelLaptopGamingTDKInterface@@QAEHXZ",
          IntelGet80211SignalStrength, 0) {
  return 0;
}

}  // namespace recomp::hle
