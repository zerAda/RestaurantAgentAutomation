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
            <Flex justifyContent="space-between" paddingBottom={2}>
                <Flex gap={2} alignItems="center">
                    <Typography variant="pi" fontWeight="bold">
                        {intlLabel?.defaultMessage || name}
                    </Typography>
                    <Badge>{entries.length} fields</Badge>
                </Flex>
                <Button variant="ghost" size="S" onClick={() => setMode('raw')}>
                    {'{ }'} Raw JSON
                </Button>
            </Flex>
            <Box
                padding={4}
                background="neutral100"
                borderColor="neutral200"
                hasRadius
            >
                <Stack spacing={3}>
                    {entries.map(([key, val]) => renderField(key, val))}
                </Stack>
            </Box>
            {description && (
                <Typography variant="pi" textColor="neutral600">
                    {description?.defaultMessage || description}
                </Typography>
            )}
            {error && (
                <Typography variant="pi" textColor="danger600">
                    {error}
                </Typography>
            )}
        </Box>
    );
};

export default JsonFormInput;
