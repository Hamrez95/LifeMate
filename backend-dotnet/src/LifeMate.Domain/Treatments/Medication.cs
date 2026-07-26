using LifeMate.Domain.Common;

namespace LifeMate.Domain.Treatments;

public sealed class Medication
{
    private Medication()
    {
        Name = string.Empty;
    }

    public Medication(
        Guid ownerUserId,
        string name,
        string? strengthText,
        string? form,
        string? notes,
        DateTime utcNow)
    {
        if (ownerUserId == Guid.Empty) throw new DomainException("Medication owner is required.");
        Validate(name, strengthText, form, notes);
        EnsureUtc(utcNow);

        Id = Guid.NewGuid();
        OwnerUserId = ownerUserId;
        Name = name.Trim();
        StrengthText = NormalizeOptional(strengthText);
        Form = NormalizeOptional(form);
        Notes = NormalizeOptional(notes);
        Version = 1;
        CreatedAtUtc = utcNow;
        UpdatedAtUtc = utcNow;
    }

    public Guid Id { get; private set; }
    public Guid OwnerUserId { get; private set; }
    public string Name { get; private set; }
    public string? StrengthText { get; private set; }
    public string? Form { get; private set; }
    public string? Notes { get; private set; }
    public int Version { get; private set; }
    public DateTime CreatedAtUtc { get; private set; }
    public DateTime UpdatedAtUtc { get; private set; }

    public void Update(
        string name,
        string? strengthText,
        string? form,
        string? notes,
        DateTime utcNow)
    {
        Validate(name, strengthText, form, notes);
        EnsureUtc(utcNow);

        Name = name.Trim();
        StrengthText = NormalizeOptional(strengthText);
        Form = NormalizeOptional(form);
        Notes = NormalizeOptional(notes);
        Version++;
        UpdatedAtUtc = utcNow;
    }

    private static void Validate(string name, string? strengthText, string? form, string? notes)
    {
        if (string.IsNullOrWhiteSpace(name) || name.Trim().Length > 120)
            throw new DomainException("Medication name is required and must be 120 characters or fewer.");
        if (strengthText?.Trim().Length > 80)
            throw new DomainException("Medication strength must be 80 characters or fewer.");
        if (form?.Trim().Length > 50)
            throw new DomainException("Medication form must be 50 characters or fewer.");
        if (notes?.Trim().Length > 500)
            throw new DomainException("Medication notes must be 500 characters or fewer.");
    }

    private static string? NormalizeOptional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();

    private static DateTime EnsureUtc(DateTime value) =>
        value.Kind == DateTimeKind.Utc
            ? value
            : throw new DomainException("Timestamps must be UTC.");
}
