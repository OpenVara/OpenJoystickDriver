#include <SDL3/SDL.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#
static const char *env_or_unset(const char *key) {
  const char *v = getenv(key);
  return v ? v : "(unset)";
}
#
static void print_joystick_id(SDL_JoystickID id) {
  const char *joystick_name = SDL_GetJoystickNameForID(id);
  const char *gamepad_name = SDL_GetGamepadNameForID(id);
  Uint16 vid = SDL_GetJoystickVendorForID(id);
  Uint16 pid = SDL_GetJoystickProductForID(id);
  Uint16 ver = SDL_GetJoystickProductVersionForID(id);
  SDL_GUID guid = SDL_GetJoystickGUIDForID(id);
  char guid_str[64];
  SDL_GUIDToString(guid, guid_str, (int)sizeof(guid_str));
#
  printf("- id=%u vid=0x%04x pid=0x%04x ver=0x%04x guid=%s\n", (unsigned)id, vid, pid, ver, guid_str);
  printf("  joystick_name=%s\n", joystick_name ? joystick_name : "(null)");
  printf("  is_gamepad=%s gamepad_name=%s\n", SDL_IsGamepad(id) ? "yes" : "no", gamepad_name ? gamepad_name : "(null)");
#
  SDL_Joystick *joy = SDL_OpenJoystick(id);
  if (joy) {
    const char *serial = SDL_GetJoystickSerial(joy);
    printf("  serial=%s\n", serial ? serial : "(null)");
    SDL_CloseJoystick(joy);
  } else {
    printf("  open_joystick_failed=%s\n", SDL_GetError());
  }
#
  if (SDL_IsGamepad(id)) {
    char *mapping = SDL_GetGamepadMappingForID(id);
    if (mapping) {
      printf("  mapping=%s\n", mapping);
      SDL_free(mapping);
    } else {
      printf("  mapping=(null)\n");
    }
  }
}
#
static int parse_seconds(int argc, char **argv) {
  for (int i = 1; i < argc; i++) {
    if (strcmp(argv[i], "--seconds") == 0 && (i + 1) < argc) {
      int s = atoi(argv[i + 1]);
      if (s <= 0) s = 10;
      if (s > 60) s = 60;
      return s;
    }
  }
  return 10;
}
#
int main(int argc, char **argv) {
  int seconds = parse_seconds(argc, argv);
#
  int v = SDL_GetVersion();
  int major = SDL_VERSIONNUM_MAJOR(v);
  int minor = SDL_VERSIONNUM_MINOR(v);
  int patch = SDL_VERSIONNUM_MICRO(v);
#
  printf("SDL linked version: %d.%d.%d (raw=%d)\n", major, minor, patch, v);
  printf("SDL_JOYSTICK_MFI=%s\n", env_or_unset("SDL_JOYSTICK_MFI"));
  printf("SDL_JOYSTICK_IOKIT=%s\n", env_or_unset("SDL_JOYSTICK_IOKIT"));
#
  if (!SDL_Init(SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK | SDL_INIT_EVENTS)) {
    fprintf(stderr, "ERROR: SDL_Init failed: %s\n", SDL_GetError());
    fprintf(stderr, "\nWhat to do:\n");
    fprintf(stderr, "  - Make sure your terminal app has Input Monitoring permission.\n");
    fprintf(stderr, "    System Settings -> Privacy & Security -> Input Monitoring\n");
    return 2;
  }
#
  int joy_count = 0;
  SDL_JoystickID *joy_ids = SDL_GetJoysticks(&joy_count);
  printf("\nFound %d joystick(s)\n", joy_count);
  for (int i = 0; i < joy_count; i++) {
    print_joystick_id(joy_ids[i]);
  }
  SDL_free(joy_ids);
#
  if (joy_count == 0) {
    printf("\nNOTE: SDL sees 0 devices.\n");
    printf("  This typically means either:\n");
    printf("  1) Your terminal app lacks Input Monitoring permission, OR\n");
    printf("  2) SDL's backend is filtering the device out (common for some virtual HID sources).\n");
    printf("\nNext steps:\n");
    printf("  - Grant Input Monitoring to the terminal app and relaunch it.\n");
    printf("  - If PCSX2 sees devices but this probe doesn't, PCSX2 may be running under a different\n");
    printf("    architecture (Rosetta) / different SDL build.\n");
  }
#
  printf("\nListening for %ds (press buttons now) ...\n", seconds);
  Uint64 start = SDL_GetTicks();
  Uint64 last = start;
  while ((SDL_GetTicks() - start) < (Uint64)(seconds * 1000)) {
    SDL_Event e;
    while (SDL_PollEvent(&e)) {
      Uint64 now = SDL_GetTicks();
      Uint64 delta = now - last;
      last = now;
      switch (e.type) {
        case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
        case SDL_EVENT_GAMEPAD_BUTTON_UP:
          printf("[t=%llums +%llums] GAMEPAD_BUTTON %s which=%u button=%d\n",
                 (unsigned long long)now,
                 (unsigned long long)delta,
                 (e.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) ? "down" : "up",
                 (unsigned)e.gbutton.which,
                 (int)e.gbutton.button);
          break;
        case SDL_EVENT_GAMEPAD_AXIS_MOTION:
          if (abs((int)e.gaxis.value) > 8000) {
            printf("[t=%llums +%llums] GAMEPAD_AXIS which=%u axis=%d value=%d\n",
                   (unsigned long long)now,
                   (unsigned long long)delta,
                   (unsigned)e.gaxis.which,
                   (int)e.gaxis.axis,
                   (int)e.gaxis.value);
          }
          break;
        case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
        case SDL_EVENT_JOYSTICK_BUTTON_UP:
          printf("[t=%llums +%llums] JOY_BUTTON %s which=%u button=%d\n",
                 (unsigned long long)now,
                 (unsigned long long)delta,
                 (e.type == SDL_EVENT_JOYSTICK_BUTTON_DOWN) ? "down" : "up",
                 (unsigned)e.jbutton.which,
                 (int)e.jbutton.button);
          break;
        case SDL_EVENT_JOYSTICK_AXIS_MOTION:
          if (abs((int)e.jaxis.value) > 8000) {
            printf("[t=%llums +%llums] JOY_AXIS which=%u axis=%d value=%d\n",
                   (unsigned long long)now,
                   (unsigned long long)delta,
                   (unsigned)e.jaxis.which,
                   (int)e.jaxis.axis,
                   (int)e.jaxis.value);
          }
          break;
        default:
          break;
      }
    }
    SDL_Delay(1);
  }
#
  SDL_Quit();
  return 0;
}

