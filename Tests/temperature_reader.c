#include <IOKit/IOKitLib.h>

static kern_return_t fake_smc(io_connect_t connection, uint32_t selector,
    const void *input, size_t input_size, void *output, size_t *output_size);
#define IOConnectCallStructMethod fake_smc
#include "../Sources/CaffelidSensors/Temperature.c"
#include <assert.h>
#include <stdio.h>

static uint8_t readings[2][32];
static bool fail_read[2];
static kern_return_t fake_smc(io_connect_t connection, uint32_t selector,
    const void *input, size_t input_size, void *output, size_t *output_size) {
    (void)connection;
    assert(selector == 2 && input_size == sizeof(SMCMessage) && *output_size == sizeof(SMCMessage));
    const SMCMessage *request = input;
    assert(request->command == 5); // This test exercises only temperature reads.
    SMCMessage *response = output;
    memset(response, 0, sizeof(*response));
    size_t index = request->key == fourcc("Tp01") ? 0 : 1;
    if (fail_read[index]) return kIOReturnError;
    memcpy(response->bytes, readings[index], 32);
    return KERN_SUCCESS;
}

static void set_float(float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    for (unsigned i = 0; i < 4; i++) readings[0][i] = (uint8_t)(bits >> (i * 8));
}

int main(void) {
    CaffelidTemperatureReader reader = { .count = 2, .sensors = {
        { .key = 0, .info = { .size = 4 } }, { .key = 0, .info = { .size = 2 } }
    } };
    reader.sensors[0].key = fourcc("Tp01");
    reader.sensors[0].info.type = fourcc("flt ");
    reader.sensors[1].key = fourcc("TC0P");
    reader.sensors[1].info.type = fourcc("sp78");
    readings[1][0] = 80; readings[1][1] = 128; // Big-endian signed fixed point: 80.5 °C.
    set_float(95.25f); // Little-endian Apple Silicon float.
    double temperature = -1;
    size_t count = 0;
    assert(caffelid_temperature_read(&reader, &temperature, &count) == 0);
    assert(temperature == 95.25 && count == 2);
    set_float(60);
    assert(caffelid_temperature_read(&reader, &temperature, &count) == 0);
    assert(temperature == 80.5 && count == 2);
    float invalid[] = { NAN, INFINITY, -1, 0, 151 };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        set_float(invalid[i]);
        assert(caffelid_temperature_read(&reader, &temperature, &count) == 0);
        assert(temperature == 80.5 && count == 1);
    }
    readings[1][0] = 255; readings[1][1] = 0; // -1 °C, not 255 °C.
    assert(caffelid_temperature_read(&reader, &temperature, &count) == -1);
    set_float(95);
    fail_read[1] = true;
    assert(caffelid_temperature_read(&reader, &temperature, &count) == 0 && temperature == 95 && count == 1);
    fail_read[0] = true;
    assert(caffelid_temperature_read(&reader, &temperature, &count) == -1);
    assert(caffelid_temperature_read(NULL, &temperature, &count) == -1);
    assert(caffelid_temperature_read(&reader, NULL, &count) == -1);
    assert(caffelid_temperature_read(&reader, &temperature, NULL) == -1);
    puts("Temperature decoding, maximum selection and unavailable readings: passed");
    return 0;
}
