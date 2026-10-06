#include "CaffelidSensors.h"
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

// Read-only AppleSMC wire layout. Only key information, enumeration and read
// commands are implemented; no fan, power or temperature settings can be written.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } SMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } SMCPowerLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } SMCKeyInfo;
typedef struct {
    uint32_t key;
    SMCVersion version;
    SMCPowerLimits power;
    SMCKeyInfo info;
    uint8_t result, status, command;
    uint32_t index;
    uint8_t bytes[32];
} SMCMessage;
_Static_assert(sizeof(SMCMessage) == 80, "Unexpected AppleSMC ABI");

typedef struct { uint32_t key; SMCKeyInfo info; } Sensor;
struct CaffelidTemperatureReader {
    io_connect_t connection;
    size_t count;
    Sensor sensors[256];
};

static uint32_t fourcc(const char *text) {
    return (uint32_t)(uint8_t)text[0] << 24 | (uint32_t)(uint8_t)text[1] << 16 |
        (uint32_t)(uint8_t)text[2] << 8 | (uint32_t)(uint8_t)text[3];
}

static int call(CaffelidTemperatureReader *reader, SMCMessage *request, SMCMessage *response) {
    memset(response, 0, sizeof(*response));
    size_t size = sizeof(*response);
    kern_return_t result = IOConnectCallStructMethod(reader->connection, 2,
        request, sizeof(*request), response, &size);
    return result == KERN_SUCCESS && size == sizeof(*response) && response->result == 0 ? 0 : -1;
}

static int key_info(CaffelidTemperatureReader *reader, uint32_t key, SMCKeyInfo *info) {
    SMCMessage request = {0}, response;
    request.key = key;
    request.command = 9;
    if (call(reader, &request, &response) != 0) return -1;
    *info = response.info;
    return 0;
}

static int read_sensor(CaffelidTemperatureReader *reader, Sensor sensor, uint8_t bytes[32]) {
    SMCMessage request = {0}, response;
    if (sensor.info.size == 0 || sensor.info.size > sizeof(response.bytes)) return -1;
    request.key = sensor.key;
    request.info.size = sensor.info.size;
    request.command = 5;
    if (call(reader, &request, &response) != 0) return -1;
    memcpy(bytes, response.bytes, 32);
    return 0;
}

CaffelidTemperatureReader *caffelid_temperature_reader_create(void) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == 0) return NULL;
    CaffelidTemperatureReader *reader = calloc(1, sizeof(*reader));
    if (!reader) { IOObjectRelease(service); return NULL; }
    kern_return_t opened = IOServiceOpen(service, mach_task_self(), 0, &reader->connection);
    IOObjectRelease(service);
    if (opened != KERN_SUCCESS) { free(reader); return NULL; }
    Sensor total = { .key = fourcc("#KEY") };
    uint8_t bytes[32];
    if (key_info(reader, total.key, &total.info) != 0 || total.info.size != 4 ||
        read_sensor(reader, total, bytes) != 0) goto failed;
    uint32_t count = (uint32_t)bytes[0] << 24 | (uint32_t)bytes[1] << 16 |
        (uint32_t)bytes[2] << 8 | bytes[3];
    if (count == 0 || count > 10000) goto failed;
    for (uint32_t i = 0; i < count; i++) {
        SMCMessage request = {0}, response;
        request.command = 8;
        request.index = i;
        if (call(reader, &request, &response) != 0) continue;
        char first = (char)(response.key >> 24), second = (char)(response.key >> 16);
        // CPU/performance/efficiency and GPU sensors; exclude battery and ambient
        // sensors so the setting measures processor heat, not enclosure temperature.
        if (first != 'T' || (second != 'p' && second != 'g' && second != 'C' && second != 'G')) continue;
        Sensor sensor = { .key = response.key };
        if (key_info(reader, sensor.key, &sensor.info) != 0) continue;
        bool supported = (sensor.info.type == fourcc("flt ") && sensor.info.size == 4) ||
            (sensor.info.type == fourcc("sp78") && sensor.info.size == 2);
        if (!supported) continue;
        if (reader->count == sizeof(reader->sensors) / sizeof(reader->sensors[0])) goto failed;
        reader->sensors[reader->count++] = sensor;
    }
    if (reader->count == 0) goto failed;
    return reader;
failed:
    caffelid_temperature_reader_destroy(reader);
    return NULL;
}

void caffelid_temperature_reader_destroy(CaffelidTemperatureReader *reader) {
    if (!reader) return;
    if (reader->connection != 0) IOServiceClose(reader->connection);
    free(reader);
}

int caffelid_temperature_read(CaffelidTemperatureReader *reader, double *temperature, size_t *sensor_count) {
    if (!reader || !temperature || !sensor_count) return -1;
    double highest = 0;
    size_t valid = 0;
    for (size_t i = 0; i < reader->count; i++) {
        Sensor sensor = reader->sensors[i];
        uint8_t bytes[32];
        if (read_sensor(reader, sensor, bytes) != 0) continue;
        double value;
        if (sensor.info.type == fourcc("flt ")) {
            uint32_t bits = (uint32_t)bytes[0] | (uint32_t)bytes[1] << 8 |
                (uint32_t)bytes[2] << 16 | (uint32_t)bytes[3] << 24;
            float number;
            memcpy(&number, &bits, sizeof(number));
            value = number;
        } else {
            int16_t fixed = (int16_t)((uint16_t)bytes[0] << 8 | bytes[1]);
            value = fixed / 256.0;
        }
        if (!isfinite(value) || value <= 0 || value > 150) continue;
        if (value > highest) highest = value;
        valid++;
    }
    if (valid == 0) return -1;
    *temperature = highest;
    *sensor_count = valid;
    return 0;
}
