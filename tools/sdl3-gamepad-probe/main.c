#include <SDL3/SDL.h>
#include <errno.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(__APPLE__)
    #include <TargetConditionals.h>
#endif

static const char *OJD_GUIDS[] = {
    "0300f88c4a4f00004844000008040000",  // OpenJoystickDriver generic user-space profile
};
static const int OJD_GUID_COUNT = (int)(sizeof(OJD_GUIDS) / sizeof(OJD_GUIDS[0]));

static const char *env_or_unset(const char *key) {
    const char *v = getenv(key);
    return v ? v : "(unset)";
}

static int has_flag(int argc, char **argv, const char *flag) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], flag) == 0)
            return 1;
    }
    return 0;
}

static int is_ojd_guid(const char *guid) {
    for (int i = 0; i < OJD_GUID_COUNT; i++) {
        if (strcmp(guid, OJD_GUIDS[i]) == 0)
            return 1;
    }
    return 0;
}

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
    printf(
        "- id=%u vid=0x%04x pid=0x%04x ver=0x%04x guid=%s\n",
        (unsigned)id,
        vid,
        pid,
        ver,
        guid_str);
    printf("  joystick_name=%s\n", joystick_name ? joystick_name : "(null)");
    printf(
        "  is_gamepad=%s gamepad_name=%s\n",
        SDL_IsGamepad(id) ? "yes" : "no",
        gamepad_name ? gamepad_name : "(null)");
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

        SDL_Gamepad *gamepad = SDL_OpenGamepad(id);
        if (gamepad) {
            printf("  gamepad_axes:");
            for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT; axis++) {
                printf(" a%d=%d", axis, SDL_GetGamepadAxis(gamepad, (SDL_GamepadAxis)axis));
            }
            printf("\n");
            printf("  gamepad_buttons:");
            for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT; button++) {
                printf(" b%d=%d", button, SDL_GetGamepadButton(gamepad, (SDL_GamepadButton)button));
            }
            printf("\n");
            SDL_CloseGamepad(gamepad);
        } else {
            printf("  open_gamepad_failed=%s\n", SDL_GetError());
        }
    }
}

static int parse_seconds(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--seconds") == 0 && (i + 1) < argc) {
            int s = atoi(argv[i + 1]);
            if (s <= 0)
                s = 10;
            if (s > 60)
                s = 60;
            return s;
        }
    }
    return 10;
}

static const char *parse_mappings_file(int argc, char **argv) {
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--mappings-file") == 0 && (i + 1) < argc) {
            return argv[i + 1];
        }
    }
    return NULL;
}

static int file_exists(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f)
        return 0;
    fclose(f);
    return 1;
}

static int check_single_neutral_ojd(SDL_JoystickID *joy_ids, int joy_count) {
    int ojd_count = 0;
    int failures = 0;

    for (int i = 0; i < joy_count; i++) {
        SDL_JoystickID id = joy_ids[i];
        SDL_GUID guid = SDL_GetJoystickGUIDForID(id);
        char guid_str[64];
        SDL_GUIDToString(guid, guid_str, (int)sizeof(guid_str));
        if (!is_ojd_guid(guid_str))
            continue;

        ojd_count++;
        if (!SDL_IsGamepad(id)) {
            printf("EXPECT_FAIL: OJD device is not classified as a gamepad\n");
            failures++;
            continue;
        }

        SDL_Gamepad *gamepad = SDL_OpenGamepad(id);
        if (!gamepad) {
            printf("EXPECT_FAIL: OJD gamepad open failed: %s\n", SDL_GetError());
            failures++;
            continue;
        }

        for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT; axis++) {
            Sint16 value = SDL_GetGamepadAxis(gamepad, (SDL_GamepadAxis)axis);
            if (value != 0) {
                printf("EXPECT_FAIL: OJD idle axis %d is %d, expected 0\n", axis, value);
                failures++;
            }
        }
        for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT; button++) {
            bool pressed = SDL_GetGamepadButton(gamepad, (SDL_GamepadButton)button);
            if (pressed) {
                printf("EXPECT_FAIL: OJD idle button %d is pressed, expected released\n", button);
                failures++;
            }
        }
        SDL_CloseGamepad(gamepad);
    }

    if (ojd_count != 1) {
        printf("EXPECT_FAIL: found %d OJD gamepad(s), expected 1\n", ojd_count);
        failures++;
    }

    if (failures == 0) {
        printf("EXPECT_PASS: exactly one neutral OJD gamepad\n");
        return 0;
    }
    return 3;
}

int main(int argc, char **argv) {
    int seconds = parse_seconds(argc, argv);
    const char *mappings_file = parse_mappings_file(argc, argv);
    int expect_single_neutral_ojd = has_flag(argc, argv, "--expect-single-neutral-ojd");

    int v = SDL_GetVersion();
    int major = SDL_VERSIONNUM_MAJOR(v);
    int minor = SDL_VERSIONNUM_MINOR(v);
    int patch = SDL_VERSIONNUM_MICRO(v);

    printf("SDL linked version: %d.%d.%d (raw=%d)\n", major, minor, patch, v);
    printf("SDL platform: %s\n", SDL_GetPlatform());
    printf("SDL_JOYSTICK_MFI=%s\n", env_or_unset("SDL_JOYSTICK_MFI"));
    printf("SDL_JOYSTICK_IOKIT=%s\n", env_or_unset("SDL_JOYSTICK_IOKIT"));
    printf("SDL_JOYSTICK_HIDAPI_XBOX=%s\n", env_or_unset("SDL_JOYSTICK_HIDAPI_XBOX"));
    printf("SDL_JOYSTICK_HIDAPI_XBOX_ONE=%s\n", env_or_unset("SDL_JOYSTICK_HIDAPI_XBOX_ONE"));

    if (!SDL_Init(SDL_INIT_GAMEPAD | SDL_INIT_JOYSTICK | SDL_INIT_EVENTS)) {
        fprintf(stderr, "ERROR: SDL_Init failed: %s\n", SDL_GetError());
        fprintf(stderr, "\nWhat to do:\n");
        fprintf(stderr, "  - Make sure your terminal app has Input Monitoring permission.\n");
        fprintf(stderr, "    System Settings -> Privacy & Security -> Input Monitoring\n");
        return 2;
    }
    SDL_SetGamepadEventsEnabled(true);
    SDL_SetJoystickEventsEnabled(true);

    if (!mappings_file) {
        const char *default_db =
            "/Applications/PCSX2.app/Contents/Resources/game_controller_db.txt";
        if (file_exists(default_db))
            mappings_file = default_db;
    }

    if (mappings_file) {
        int added = SDL_AddGamepadMappingsFromFile(mappings_file);
        if (added < 0) {
            printf("\nLoaded mappings: ERROR (%s)\n", SDL_GetError());
        } else {
            printf("\nLoaded mappings: %d (%s)\n", added, mappings_file);
        }
    } else {
        printf("\nLoaded mappings: (none)\n");
    }

    int joy_count = 0;
    SDL_JoystickID *joy_ids = SDL_GetJoysticks(&joy_count);
    printf("\nFound %d joystick(s)\n", joy_count);
    for (int i = 0; i < joy_count; i++) {
        print_joystick_id(joy_ids[i]);
    }

    SDL_Gamepad **open_gamepads = NULL;
    if (joy_count > 0) {
        open_gamepads = (SDL_Gamepad **)calloc((size_t)joy_count, sizeof(SDL_Gamepad *));
        if (!open_gamepads) {
            fprintf(stderr, "ERROR: calloc failed: %s\n", strerror(errno));
            SDL_free(joy_ids);
            SDL_Quit();
            return 2;
        }
    }

    int open_gamepad_count = 0;
    for (int i = 0; i < joy_count; i++) {
        if (!SDL_IsGamepad(joy_ids[i]))
            continue;
        open_gamepads[i] = SDL_OpenGamepad(joy_ids[i]);
        if (open_gamepads[i]) {
            open_gamepad_count++;
        } else {
            printf(
                "WARN: listener could not open gamepad id=%u: %s\n",
                (unsigned)joy_ids[i],
                SDL_GetError());
        }
    }
    if (open_gamepad_count > 0) {
        printf("\nOpened %d gamepad(s) for event listening\n", open_gamepad_count);
    }

    Sint16 *last_axes = NULL;
    bool *last_buttons = NULL;
    if (joy_count > 0) {
        last_axes = (Sint16 *)calloc((size_t)joy_count * SDL_GAMEPAD_AXIS_COUNT, sizeof(Sint16));
        last_buttons = (bool *)calloc((size_t)joy_count * SDL_GAMEPAD_BUTTON_COUNT, sizeof(bool));
        if (!last_axes || !last_buttons) {
            fprintf(stderr, "ERROR: calloc failed: %s\n", strerror(errno));
            free(last_axes);
            free(last_buttons);
            free(open_gamepads);
            SDL_free(joy_ids);
            SDL_Quit();
            return 2;
        }
    }

    int expectation_result = 0;
    if (expect_single_neutral_ojd) {
        expectation_result = check_single_neutral_ojd(joy_ids, joy_count);
    }
#
    if (joy_count == 0) {
        printf("\nNOTE: SDL sees 0 devices.\n");
        printf("  This typically means either:\n");
        printf("  1) Your terminal app lacks Input Monitoring permission, OR\n");
        printf(
            "  2) SDL's backend is filtering the device out (common for some virtual HID "
            "sources).\n");
        printf("\nNext steps:\n");
        printf("  - Grant Input Monitoring to the terminal app and relaunch it.\n");
        printf(
            "  - If PCSX2 sees devices but this probe doesn't, PCSX2 may be running under a "
            "different\n");
        printf("    architecture (Rosetta) / different SDL build.\n");
    }

    printf("\nListening for %ds (press buttons now) ...\n", seconds);
    Uint64 start = SDL_GetTicks();
    Uint64 last = start;
    while ((SDL_GetTicks() - start) < (Uint64)(seconds * 1000)) {
        SDL_UpdateGamepads();
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            Uint64 now = SDL_GetTicks();
            Uint64 delta = now - last;
            last = now;
            switch (e.type) {
                case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
                case SDL_EVENT_GAMEPAD_BUTTON_UP:
                    printf(
                        "[t=%llums +%llums] GAMEPAD_BUTTON %s which=%u button=%d\n",
                        (unsigned long long)now,
                        (unsigned long long)delta,
                        (e.type == SDL_EVENT_GAMEPAD_BUTTON_DOWN) ? "down" : "up",
                        (unsigned)e.gbutton.which,
                        (int)e.gbutton.button);
                    break;
                case SDL_EVENT_GAMEPAD_AXIS_MOTION:
                    if (abs((int)e.gaxis.value) > 8000) {
                        printf(
                            "[t=%llums +%llums] GAMEPAD_AXIS which=%u axis=%d value=%d\n",
                            (unsigned long long)now,
                            (unsigned long long)delta,
                            (unsigned)e.gaxis.which,
                            (int)e.gaxis.axis,
                            (int)e.gaxis.value);
                    }
                    break;
                case SDL_EVENT_JOYSTICK_BUTTON_DOWN:
                case SDL_EVENT_JOYSTICK_BUTTON_UP:
                    printf(
                        "[t=%llums +%llums] JOY_BUTTON %s which=%u button=%d\n",
                        (unsigned long long)now,
                        (unsigned long long)delta,
                        (e.type == SDL_EVENT_JOYSTICK_BUTTON_DOWN) ? "down" : "up",
                        (unsigned)e.jbutton.which,
                        (int)e.jbutton.button);
                    break;
                case SDL_EVENT_JOYSTICK_AXIS_MOTION:
                    if (abs((int)e.jaxis.value) > 8000) {
                        printf(
                            "[t=%llums +%llums] JOY_AXIS which=%u axis=%d value=%d\n",
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
        for (int i = 0; i < joy_count; i++) {
            SDL_Gamepad *gamepad = open_gamepads ? open_gamepads[i] : NULL;
            if (!gamepad)
                continue;
            for (int axis = 0; axis < SDL_GAMEPAD_AXIS_COUNT; axis++) {
                Sint16 value = SDL_GetGamepadAxis(gamepad, (SDL_GamepadAxis)axis);
                Sint16 *last_value = &last_axes[(i * SDL_GAMEPAD_AXIS_COUNT) + axis];
                if (abs((int)value - (int)*last_value) > 8000) {
                    Uint64 now = SDL_GetTicks();
                    printf(
                        "[t=%llums] GAMEPAD_STATE_AXIS id=%u axis=%d value=%d\n",
                        (unsigned long long)now,
                        (unsigned)joy_ids[i],
                        axis,
                        value);
                    *last_value = value;
                }
            }
            for (int button = 0; button < SDL_GAMEPAD_BUTTON_COUNT; button++) {
                bool pressed = SDL_GetGamepadButton(gamepad, (SDL_GamepadButton)button);
                bool *last_value = &last_buttons[(i * SDL_GAMEPAD_BUTTON_COUNT) + button];
                if (pressed != *last_value) {
                    Uint64 now = SDL_GetTicks();
                    printf(
                        "[t=%llums] GAMEPAD_STATE_BUTTON id=%u button=%d value=%d\n",
                        (unsigned long long)now,
                        (unsigned)joy_ids[i],
                        button,
                        pressed ? 1 : 0);
                    *last_value = pressed;
                }
            }
        }
        SDL_Delay(1);
    }

    free(last_axes);
    free(last_buttons);
    if (open_gamepads) {
        for (int i = 0; i < joy_count; i++) {
            if (open_gamepads[i])
                SDL_CloseGamepad(open_gamepads[i]);
        }
        free(open_gamepads);
    }
    SDL_free(joy_ids);
    SDL_Quit();
    return expectation_result;
}
