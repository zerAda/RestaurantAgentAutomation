import React, { useState, useCallback, useMemo } from 'react';
import {
    Box,
    TextInput,
    ToggleInput,
    NumberInput,
    Typography,
    Stack,
    Flex,
    Button,
    Textarea,
    Badge,
} from '@strapi/design-system';

/**
 * JsonFormInput — Renders a JSON object as a set of typed form fields.
 * 
 * Supports: string, number, boolean, and nested objects (1 level).
 * Falls back to a raw JSON textarea for complex/unknown structures.
 */
const JsonFormInput = ({
    name,
    value,
    onChange,
    attribute,
    intlLabel,
    description,
    error,
    required,
    disabled,
}) => {
    const [mode, setMode] = useState('form'); // 'form' | 'raw'

    const parsed = useMemo(() => {
        try {
            if (typeof value === 'object' && value !== null) return value;
            return JSON.parse(value || '{}');
        } catch {
            return null;
        }
    }, [value]);

    const [rawValue, setRawValue] = useState(
        typeof value === 'string' ? value : JSON.stringify(value || {}, null, 2)
    );

    const emitChange = useCallback(
        (newObj) => {
            onChange({
                target: {
                    name,
                    value: JSON.stringify(newObj),
                    type: attribute.type,
                },
            });
        },
        [name, onChange, attribute]
    );

    const handleFieldChange = useCallback(
        (key, fieldValue) => {
            const updated = { ...(parsed || {}), [key]: fieldValue };
            emitChange(updated);
            setRawValue(JSON.stringify(updated, null, 2));
        },
        [parsed, emitChange]
    );

    const handleRawChange = useCallback(
        (e) => {
            const raw = e.target.value;
            setRawValue(raw);
            try {
                const obj = JSON.parse(raw);
                onChange({
                    target: { name, value: raw, type: attribute.type },
                });
            } catch {
                // Invalid JSON — keep local but don't emit
            }
        },
        [name, onChange, attribute]
    );

    const renderField = (key, val) => {
        const fieldType = typeof val;

        if (fieldType === 'boolean') {
            return (
                <ToggleInput
                    key={key}
                    label={key}
                    name={`${name}.${key}`}
                    checked={val}
                    onChange={(e) => handleFieldChange(key, e.target.checked)}
                    disabled={disabled}
                    onLabel="On"
                    offLabel="Off"
                    size="S"
                />
            );
        }

        if (fieldType === 'number') {
            return (
                <NumberInput
                    key={key}
                    label={key}
                    name={`${name}.${key}`}
                    value={val}
                    onValueChange={(v) => handleFieldChange(key, v)}
                    disabled={disabled}
                />
            );
        }

        if (fieldType === 'string' && val.length > 80) {
            return (
                <Textarea
                    key={key}
                    label={key}
                    name={`${name}.${key}`}
                    value={val}
                    onChange={(e) => handleFieldChange(key, e.target.value)}
                    disabled={disabled}
                />
            );
        }

        return (
            <TextInput
                key={key}
                label={key}
                name={`${name}.${key}`}
                value={String(val ?? '')}
                onChange={(e) => handleFieldChange(key, e.target.value)}
                disabled={disabled}
            />
        );
    };

    if (!parsed || mode === 'raw') {
        return (
            <Box>
                <Flex justifyContent="space-between" paddingBottom={2}>
                    <Typography variant="pi" fontWeight="bold">
                        {intlLabel?.defaultMessage || name}
                    </Typography>
                    {parsed && (
                        <Button variant="ghost" size="S" onClick={() => setMode('form')}>
                            📋 Form View
                        </Button>
                    )}
                </Flex>
                <Textarea
                    name={name}
                    value={rawValue}
                    onChange={handleRawChange}
                    disabled={disabled}
                    placeholder='{"key": "value"}'
                    style={{ fontFamily: 'monospace', minHeight: 200 }}
                />
                {error && (
                    <Typography variant="pi" textColor="danger600">
                        {error}
                    </Typography>
                )}
            </Box>
        );
    }

    const entries = Object.entries(parsed);

    return (
        <Box>
            <Flex justifyContent="space-between" paddingBottom={4} paddingTop={2}>
                <Flex gap={3} alignItems="center">
                    <Typography variant="beta" fontWeight="bold">
                        {intlLabel?.defaultMessage || name}
                    </Typography>
                    <Badge active>{entries.length} Keys</Badge>
                </Flex>
            </Flex>

            <Flex gap={4} alignItems="stretch" style={{ minHeight: '400px' }}>
                {/* Left Side: Clean Form View */}
                <Box
                    flex={1}
                    padding={5}
                    background="neutral0"
                    borderColor="neutral200"
                    hasRadius
                    shadow="tableShadow"
                    style={{ border: '1px solid var(--color-neutral-200)' }}
                >
                    <Typography variant="sigma" textColor="neutral500" textTransform="uppercase" paddingBottom={4} display="block">
                        Structured Editor
                    </Typography>
                    <Stack spacing={4}>
                        {entries.map(([key, val]) => renderField(key, val))}
                    </Stack>
                </Box>

                {/* Right Side: Raw Code View */}
                <Box
                    flex={1}
                    padding={0}
                    background="neutral100"
                    borderColor="neutral200"
                    hasRadius
                    style={{ border: '1px solid var(--color-neutral-200)', overflow: 'hidden', display: 'flex', flexDirection: 'column' }}
                >
                    <Box padding={3} borderBottom="1px solid var(--color-neutral-200)" background="neutral150">
                        <Typography variant="sigma" textColor="neutral500" textTransform="uppercase">
                            Raw JSON Payload
                        </Typography>
                    </Box>
                    <Textarea
                        name={name}
                        value={rawValue}
                        onChange={handleRawChange}
                        disabled={disabled}
                        style={{
                            fontFamily: '"Roboto Mono", monospace',
                            flex: 1,
                            border: 'none',
                            background: 'transparent',
                            color: 'var(--color-neutral-800)',
                            padding: '16px',
                            minHeight: '350px'
                        }}
                    />
                </Box>
            </Flex>

            {description && (
                <Box paddingTop={2}>
                    <Typography variant="pi" textColor="neutral600">
                        {description?.defaultMessage || description}
                    </Typography>
                </Box>
            )}
            {error && (
                <Box paddingTop={2}>
                    <Typography variant="pi" textColor="danger600">
                        {error}
                    </Typography>
                </Box>
            )}
        </Box>
    );
};

export default JsonFormInput;
